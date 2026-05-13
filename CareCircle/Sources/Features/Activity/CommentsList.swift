import OSLog
import SwiftData
import SwiftUI

// MARK: - CommentsList

struct CommentsList: View {
    let activity: Activity
    let author: ActivityAuthorContext
    let canComment: Bool

    @Environment(\.modelContext) private var modelContext
    @FocusState private var bodyFocused: Bool
    @State private var draft = ""

    private var sortedComments: [ActivityComment] {
        activity.comments.sorted(by: { $0.createdAt < $1.createdAt })
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            SectionHeader(title: "Comments (\(sortedComments.count))")

            if sortedComments.isEmpty {
                Text("No comments yet.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                    ForEach(sortedComments) { comment in
                        commentRow(comment)
                    }
                }
            }

            if canComment {
                composer
            }
        }
    }

    private func commentRow(_ comment: ActivityComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.tightSpacing) {
                Text(displayLabel(for: comment))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(comment.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
                Spacer(minLength: 0)
                if comment.authorAppleUserID == author.appleUserID, author.hasIdentity {
                    Button(role: .destructive) {
                        delete(comment)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.ccDanger)
                    .accessibilityLabel("Delete comment")
                }
            }
            Text(comment.body)
                .font(.body)
                .foregroundStyle(Color.ccText)
        }
        .padding(Theme.tightSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Theme.tightSpacing) {
            TextField("Add a comment", text: $draft, axis: .vertical)
                .lineLimit(1 ... 4)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(Color.ccSurface)
                )
                .focused($bodyFocused)
                .accessibilityLabel("New comment")

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(trimmedDraft.isEmpty ? Color.ccSecondary : Color.ccPrimary)
            }
            .buttonStyle(.plain)
            .disabled(trimmedDraft.isEmpty)
            .accessibilityLabel("Send comment")
        }
    }

    private func displayLabel(for comment: ActivityComment) -> String {
        if comment.authorAppleUserID == author.appleUserID, author.hasIdentity {
            return "\(comment.authorDisplayName) (You)"
        }
        return comment.authorDisplayName
    }

    private func send() {
        guard !trimmedDraft.isEmpty, author.hasIdentity else { return }
        let comment = ActivityComment(
            body: trimmedDraft,
            authorAppleUserID: author.appleUserID,
            authorDisplayName: author.displayName
        )
        comment.activity = activity
        modelContext.insert(comment)
        do {
            try modelContext.save()
            draft = ""
            bodyFocused = false
        } catch {
            AppLogger.persistence.error(
                "Failed to save comment: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func delete(_ comment: ActivityComment) {
        modelContext.delete(comment)
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to delete comment: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
