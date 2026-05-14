import OSLog
import SwiftData
import SwiftUI

// MARK: - ShiftDigestComposerView

/// Voice-first composer for an end-of-shift digest. The caregiver picks
/// a shift window (defaults to the last 4 hours), records a short voice
/// memo, and submits. The submit pass:
///
/// 1. Snapshots structured care events inside the window via
///    `ShiftArtifactBuilder` so the digest detail view always renders
///    what was true at compose time.
/// 2. Runs entity extraction off the redacted transcript via the same
///    `EntityExtractorFactory` flow that powers voice activities.
/// 3. Persists the `ShiftDigest` locally so CloudKit replicates inside
///    the family.
/// 4. Enqueues a `create_shift_digest` sync op so the Railway backend
///    stores the encrypted record + fans out a realtime change.
struct ShiftDigestComposerView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(BackendInferenceClient.self) private var inferenceClient

    @State private var service = VoiceCaptureService()
    @State private var shiftStartAt: Date
    @State private var shiftEndAt: Date
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(circle: Circle, author: ActivityAuthorContext) {
        self.circle = circle
        self.author = author
        let end = Date()
        let start = end.addingTimeInterval(-4 * 60 * 60)
        _shiftStartAt = State(initialValue: start)
        _shiftEndAt = State(initialValue: end)
    }

    private var window: ClosedRange<Date> {
        let lower = min(shiftStartAt, shiftEndAt)
        let upper = max(shiftStartAt, shiftEndAt)
        return lower ... upper
    }

    private var artifactPreview: ShiftDigestArtifactsSnapshot {
        ShiftArtifactBuilder.build(
            circle: circle,
            shiftStartAt: window.lowerBound,
            shiftEndAt: window.upperBound
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacing) {
                    windowSection
                    artifactsSection
                    recorderSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Color.ccDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.spacing)
                    }
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, Theme.looseSpacing)
            }
            .background(Color.ccBackground)
            .navigationTitle("End-of-shift digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(service.state.isBusy || isSubmitting)
            .safeAreaInset(edge: .bottom) {
                DisclaimerFooter()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                service.cancel()
                dismiss()
            }
            .disabled(isSubmitting)
        }
    }

    private var windowSection: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            SectionHeader(title: "Shift window")
            VStack(spacing: Theme.tightSpacing) {
                DatePicker(
                    "Started",
                    selection: $shiftStartAt,
                    in: ...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                DatePicker(
                    "Ended",
                    selection: $shiftEndAt,
                    in: shiftStartAt ... Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .padding(Theme.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.ccSurface)
            )
        }
    }

    private var artifactsSection: some View {
        let snapshot = artifactPreview
        return VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            SectionHeader(title: "What was logged")
            if snapshot.isEmpty {
                Text("Nothing logged in this window yet — your voice note will still be saved.")
                    .font(.subheadline)
                    .foregroundStyle(Color.ccSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                            .fill(Color.ccSurface)
                    )
            } else {
                ShiftDigestArtifactsView(snapshot: snapshot)
            }
        }
    }

    private var recorderSection: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            SectionHeader(title: "Narrate the handoff")
            ShiftDigestRecorderControls(
                service: service,
                isSubmitting: isSubmitting,
                onSubmit: submit
            )
            .frame(maxWidth: .infinity)
            .padding(Theme.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.ccSurface)
            )
        }
    }

    private func submit() {
        guard case let .ready(result) = service.state else { return }
        guard author.hasIdentity else {
            service.reset()
            return
        }
        isSubmitting = true
        errorMessage = nil

        let digest = buildDigest(from: result)
        modelContext.insert(digest)

        do {
            try modelContext.save()
            syncEngine.enqueueShiftDigestCreate(digest)
            scheduleExtraction(for: digest, transcript: result.transcript)
            dismiss()
        } catch {
            modelContext.delete(digest)
            AppLogger.persistence.error(
                "Failed to save shift digest: \(String(describing: error), privacy: .public)"
            )
            errorMessage = "Couldn't save the digest. Please try again."
            isSubmitting = false
            service.reset()
        }
    }

    private func buildDigest(from result: VoiceCaptureResult) -> ShiftDigest {
        let snapshot = ShiftArtifactBuilder.build(
            circle: circle,
            shiftStartAt: window.lowerBound,
            shiftEndAt: window.upperBound
        )
        let digest = ShiftDigest(
            shiftStartAt: window.lowerBound,
            shiftEndAt: window.upperBound,
            narratorAppleUserID: author.appleUserID,
            narratorDisplayName: author.displayName,
            transcript: result.transcript,
            summary: nil,
            audioData: result.audioData,
            audioDurationSeconds: result.durationSeconds,
            extractedEntitiesJSON: nil,
            structuredArtifactsJSON: snapshot.encodedJSON(),
            relatedShiftID: nil
        )
        digest.circle = circle
        return digest
    }

    private func scheduleExtraction(for digest: ShiftDigest, transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let redactor = PHIRedactor(
            circle: circle,
            currentCaregiverDisplayName: author.displayName
        )
        let extractor = EntityExtractorFactory.makeDefault(
            redactor: redactor,
            inferenceClient: inferenceClient
        )
        ShiftDigestExtractionService.enqueue(
            digestID: digest.id,
            text: trimmed,
            extractor: extractor,
            in: modelContext
        )
    }
}
