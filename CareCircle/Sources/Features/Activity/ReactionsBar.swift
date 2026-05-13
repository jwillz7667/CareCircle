import OSLog
import SwiftData
import SwiftUI

// MARK: - ReactionsBar

struct ReactionsBar: View {
    let activity: Activity
    let author: ActivityAuthorContext
    let canReact: Bool

    @Environment(\.modelContext) private var modelContext

    static let emojiSet: [String] = ["👍", "❤️", "🙏"]

    var body: some View {
        HStack(spacing: Theme.tightSpacing) {
            ForEach(Self.emojiSet, id: \.self) { emoji in
                reactionButton(for: emoji)
            }
            Spacer(minLength: 0)
        }
    }

    private func reactionButton(for emoji: String) -> some View {
        let mine = myReactions(for: emoji)
        let count = countReactions(for: emoji)
        let isOn = !mine.isEmpty

        return Button {
            toggle(emoji: emoji, mine: mine)
        } label: {
            HStack(spacing: 4) {
                Text(emoji)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isOn ? Color.ccPrimary : Color.ccSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isOn ? Color.ccPrimary.opacity(0.15) : Color.ccSurface)
            )
            .overlay(
                Capsule()
                    .stroke(isOn ? Color.ccPrimary.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!canReact)
        .accessibilityLabel("React with \(emoji)")
        .accessibilityValue(count > 0 ? "\(count) reactions" : "No reactions")
    }

    private func countReactions(for emoji: String) -> Int {
        activity.reactions.count(where: { $0.emoji == emoji })
    }

    private func myReactions(for emoji: String) -> [ActivityReaction] {
        guard author.hasIdentity else { return [] }
        return activity.reactions.filter {
            $0.emoji == emoji && $0.authorAppleUserID == author.appleUserID
        }
    }

    private func toggle(emoji: String, mine: [ActivityReaction]) {
        guard canReact, author.hasIdentity else { return }
        if mine.isEmpty {
            let new = ActivityReaction(
                emoji: emoji,
                authorAppleUserID: author.appleUserID,
                authorDisplayName: author.displayName
            )
            new.activity = activity
            modelContext.insert(new)
        } else {
            for row in mine {
                modelContext.delete(row)
            }
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to toggle reaction: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
