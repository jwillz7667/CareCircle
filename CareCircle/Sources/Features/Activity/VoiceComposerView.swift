import OSLog
import SwiftData
import SwiftUI

// MARK: - VoiceComposerView

struct VoiceComposerView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var service = VoiceCaptureService()
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spacing) {
                statusHeader

                Spacer(minLength: 0)

                transcriptArea

                Spacer(minLength: 0)

                bottomControls
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.looseSpacing)
            .background(Color.ccBackground)
            .navigationTitle("Voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(service.state.isBusy || isSubmitting)
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

    private var statusHeader: some View {
        VStack(spacing: Theme.tightSpacing) {
            Text(headlineForState)
                .font(.headline)
                .foregroundStyle(Color.ccText)
                .multilineTextAlignment(.center)

            if case .recording = service.state {
                Text(formattedElapsed)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Color.ccPrimary)
            }

            if case let .failed(message) = service.state {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.ccDanger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.looseSpacing)
            }
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if case let .ready(result) = service.state {
            VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                Text("Transcript")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ccSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(result.transcript.isEmpty
                    ? "(Transcript unavailable — your audio is still attached.)"
                    : result.transcript)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.ccSurface)
            )
        } else if service.state.isRecording, !service.liveTranscript.isEmpty {
            ScrollView {
                Text(service.liveTranscript)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing)
            }
            .frame(maxHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.ccSurface)
            )
        } else if case .processing = service.state {
            ProgressView("Finishing up…")
                .tint(Color.ccPrimary)
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        switch service.state {
        case .ready:
            HStack(spacing: Theme.spacing) {
                Button(role: .destructive) {
                    service.reset()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.ccDanger)
                .disabled(isSubmitting)

                Button {
                    submit()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ccPrimary)
                .disabled(isSubmitting)
            }

        case .failed:
            Button {
                Task { await service.start() }
            } label: {
                Label("Try again", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ccPrimary)

        default:
            MicButton(state: service.state) {
                if service.state.isRecording {
                    Task { await service.stop() }
                } else {
                    Task { await service.start() }
                }
            }
        }
    }

    private var headlineForState: String {
        switch service.state {
        case .idle: "Hold the mic and speak"
        case .requestingPermission: "Requesting permission…"
        case .recording: "Listening…"
        case .processing: "Wrapping up…"
        case .ready: "Ready to send"
        case .failed: "Something went wrong"
        }
    }

    private var formattedElapsed: String {
        let total = Int(service.elapsedSeconds.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func submit() {
        guard case let .ready(result) = service.state else { return }
        guard author.hasIdentity else {
            service.reset()
            return
        }
        isSubmitting = true

        let activity = Activity(
            authorAppleUserID: author.appleUserID,
            authorDisplayName: author.displayName,
            type: .voiceNote,
            body: result.transcript,
            audioData: result.audioData,
            audioDurationSeconds: result.durationSeconds
        )
        activity.circle = circle
        modelContext.insert(activity)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.delete(activity)
            AppLogger.persistence.error(
                "Failed to save voice Activity: \(String(describing: error), privacy: .public)"
            )
            isSubmitting = false
            service.reset()
        }
    }
}

// MARK: - MicButton

private struct MicButton: View {
    let state: VoiceCaptureState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                SwiftUI.Circle()
                    .fill(buttonColor)
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)

                Image(systemName: state.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isRecording ? "Stop recording" : "Start recording")
        .disabled(state == .requestingPermission || state == .processing)
    }

    private var buttonColor: Color {
        switch state {
        case .recording: Color.ccDanger
        case .processing, .requestingPermission: Color.ccSecondary
        default: Color.ccPrimary
        }
    }
}
