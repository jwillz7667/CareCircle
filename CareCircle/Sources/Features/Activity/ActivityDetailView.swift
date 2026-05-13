import OSLog
import SwiftData
import SwiftUI
import UIKit

// MARK: - ActivityDetailView

struct ActivityDetailView: View {
    let activity: Activity
    let author: ActivityAuthorContext
    let permissions: CirclePermissions

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var canDelete: Bool {
        guard author.hasIdentity else { return false }
        let isAuthor = activity.authorAppleUserID == author.appleUserID
        return isAuthor || permissions.role == .owner
    }

    private var attribution: String {
        if activity.authorAppleUserID == author.appleUserID, author.hasIdentity {
            return "\(activity.authorDisplayName) (You)"
        }
        return activity.authorDisplayName.isEmpty ? "Unknown" : activity.authorDisplayName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header

                if let audioData = activity.audioData {
                    VoiceNoteRow(audioData: audioData, durationSeconds: activity.audioDurationSeconds)
                }

                if !activity.body.isEmpty {
                    Text(activity.body)
                        .font(.body)
                        .foregroundStyle(Color.ccText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let photoData = activity.photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                }

                ReactionsBar(activity: activity, author: author, canReact: permissions.canReact)

                Divider()
                    .padding(.vertical, Theme.tightSpacing / 2)

                CommentsList(activity: activity, author: author, canComment: permissions.canComment)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.spacing)
        }
        .background(Color.ccBackground)
        .navigationTitle(activity.type.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if canDelete {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Label("Delete post", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More")
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.tightSpacing) {
            Image(systemName: activity.type.systemImageName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Color.ccPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(attribution)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(activity.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func delete() {
        modelContext.delete(activity)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            AppLogger.persistence.error(
                "Failed to delete Activity: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
