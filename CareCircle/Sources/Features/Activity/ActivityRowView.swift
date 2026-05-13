import SwiftUI
import UIKit

// MARK: - ActivityRowView

struct ActivityRowView: View {
    let activity: Activity
    let author: ActivityAuthorContext

    private var attribution: String {
        if activity.authorAppleUserID == author.appleUserID, author.hasIdentity {
            return "\(activity.authorDisplayName) (You)"
        }
        return activity.authorDisplayName.isEmpty ? "Unknown" : activity.authorDisplayName
    }

    private var reactionSummary: String? {
        let total = activity.reactions.count
        guard total > 0 else { return nil }
        return total == 1 ? "1 reaction" : "\(total) reactions"
    }

    private var commentSummary: String? {
        let total = activity.comments.count
        guard total > 0 else { return nil }
        return total == 1 ? "1 comment" : "\(total) comments"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            header

            if let audio = activity.audioData {
                VoiceNoteRow(audioData: audio, durationSeconds: activity.audioDurationSeconds)
            }

            if !activity.body.isEmpty {
                Text(activity.body)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
            }

            if let photo = activity.photoData, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .accessibilityLabel("Photo attachment")
            }

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
            Image(systemName: activity.type.systemImageName)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.ccPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(attribution)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(activity.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer(minLength: 0)
            Text(activity.type.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.ccPrimary.opacity(0.12))
                )
                .foregroundStyle(Color.ccPrimary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if reactionSummary != nil || commentSummary != nil {
            HStack(spacing: Theme.spacing) {
                if let reactionSummary {
                    Label(reactionSummary, systemImage: "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                if let commentSummary {
                    Label(commentSummary, systemImage: "bubble.left")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
