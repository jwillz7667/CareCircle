import SwiftUI

// MARK: - ShiftDigestRow

/// Compact summary card for a `ShiftDigest`. Renders the shift window,
/// narrator, audio duration, and a one-line preview of the transcript
/// or summary. Used both in the dedicated digest list and inline at
/// the top of the activity feed.
struct ShiftDigestRow: View {
    let digest: ShiftDigest
    let author: ActivityAuthorContext

    private var attribution: String {
        if digest.narratorAppleUserID == author.appleUserID, author.hasIdentity {
            return "\(displayName) (You)"
        }
        return displayName
    }

    private var displayName: String {
        let trimmed = digest.narratorDisplayName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        guard let member = digest.circle?.members.first(where: { $0.appleUserID == digest.narratorAppleUserID }) else {
            return "Unknown caregiver"
        }
        let memberName = member.displayName.trimmingCharacters(in: .whitespaces)
        return memberName.isEmpty ? "Unknown caregiver" : memberName
    }

    private var preview: String {
        if let summary = digest.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty
        {
            return summary
        }
        let trimmed = digest.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return "Voice handoff saved."
    }

    private var windowText: String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: digest.shiftStartAt, to: digest.shiftEndAt)
    }

    private var durationText: String {
        let seconds = Int(digest.audioDurationSeconds.rounded())
        let minutes = seconds / 60
        let secs = seconds % 60
        return minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            header
            Text(windowText)
                .font(.caption)
                .foregroundStyle(Color.ccSecondary)
            Text(preview)
                .font(.body)
                .foregroundStyle(Color.ccText)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            footer
        }
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }

    private var header: some View {
        HStack(spacing: Theme.tightSpacing) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.ccPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(attribution)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(digest.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer(minLength: 0)
            Text("Shift digest")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.ccPrimary.opacity(0.12)))
                .foregroundStyle(Color.ccPrimary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        let counts = artifactCounts(snapshot: digest.structuredArtifacts)
        HStack(spacing: Theme.spacing) {
            if digest.audioData != nil {
                Label(durationText, systemImage: "play.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
            ForEach(counts) { item in
                Label("\(item.count) \(item.label)", systemImage: item.icon)
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func artifactCounts(snapshot: ShiftDigestArtifactsSnapshot?) -> [ArtifactCount] {
        guard let snapshot else { return [] }
        var items: [ArtifactCount] = []
        if !snapshot.doses.isEmpty {
            items.append(ArtifactCount(label: "doses", count: snapshot.doses.count, icon: "pills"))
        }
        if !snapshot.appointments.isEmpty {
            items.append(ArtifactCount(label: "appts", count: snapshot.appointments.count, icon: "calendar"))
        }
        return items
    }

    private struct ArtifactCount: Identifiable {
        let label: String
        let count: Int
        let icon: String
        var id: String {
            label
        }
    }
}
