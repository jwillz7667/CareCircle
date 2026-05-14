import OSLog
import SwiftData
import SwiftUI

// MARK: - ShiftDigestDetailView

/// Read-only detail view for an end-of-shift digest. Shows the
/// transcript + audio, the structured snapshot taken at compose time,
/// and any extracted entity chips. The narrator can delete their own
/// digests; everyone else only reads.
struct ShiftDigestDetailView: View {
    let digest: ShiftDigest
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    private var canDelete: Bool {
        digest.narratorAppleUserID == author.appleUserID && author.hasIdentity
    }

    private var attribution: String {
        let trimmed = digest.narratorDisplayName.trimmingCharacters(in: .whitespaces)
        let fallback = digest.circle?.members
            .first(where: { $0.appleUserID == digest.narratorAppleUserID })?
            .displayName.trimmingCharacters(in: .whitespaces) ?? ""
        let resolved = !trimmed.isEmpty ? trimmed : (fallback.isEmpty ? "Unknown caregiver" : fallback)
        if digest.narratorAppleUserID == author.appleUserID, author.hasIdentity {
            return "\(resolved) (You)"
        }
        return resolved
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                summaryCard
                if let audio = digest.audioData {
                    VoiceNoteRow(audioData: audio, durationSeconds: digest.audioDurationSeconds)
                }
                if !digest.transcript.isEmpty {
                    transcriptCard
                }
                if let snapshot = digest.structuredArtifacts, !snapshot.isEmpty {
                    ShiftDigestArtifactsView(snapshot: snapshot)
                }
                if let entities = digest.extractedEntities, !entities.isEmpty {
                    ExtractedEntitiesView(state: .ready(entities), compact: false)
                }
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.looseSpacing)
        }
        .background(Color.ccBackground)
        .navigationTitle("Shift digest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            DisclaimerFooter()
        }
        .confirmationDialog(
            "Delete this digest?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: delete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the digest for everyone in the Circle.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if canDelete {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete digest")
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack(spacing: Theme.tightSpacing) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title3)
                    .foregroundStyle(Color.ccPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attribution)
                        .font(.headline)
                        .foregroundStyle(Color.ccText)
                    Text(digest.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                Spacer(minLength: 0)
            }
            Text(windowText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ccText)
            if let summary = digest.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !summary.isEmpty
            {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            SectionHeader(title: "Transcript")
            Text(digest.transcript)
                .font(.body)
                .foregroundStyle(Color.ccText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacing)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                        .fill(Color.ccSurface)
                )
        }
    }

    private var windowText: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: digest.shiftStartAt, to: digest.shiftEndAt)
    }

    private func delete() {
        modelContext.delete(digest)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLogger.persistence.error(
                "Failed to delete shift digest: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
