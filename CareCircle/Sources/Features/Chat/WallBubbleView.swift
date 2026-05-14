import SwiftUI

// MARK: - WallBubbleView

/// Single bubble in the Circle Wall stream. Owns the avatar, body
/// background gradient, and the long-press context menu so the parent
/// `ChatRoomView` stays focused on data flow + composer.
struct WallBubbleView: View {
    let message: ChatMessage
    let isOwn: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !isOwn {
                avatar
            } else {
                Spacer(minLength: 32)
            }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
                if !isOwn {
                    Text(message.authorDisplayName.isEmpty ? "Member" : message.authorDisplayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.ccSecondary)
                        .padding(.leading, 2)
                }
                bubbleBody
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ccSecondary)
                    .padding(.horizontal, 4)
            }
            if isOwn {
                avatar
            } else {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    private var bubbleBody: some View {
        let isSystem = message.kind == .system
        return Text(message.body)
            .font(.body)
            .foregroundStyle(isSystem ? Color.ccPrimary : (isOwn ? Color.white : Color.ccText))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground(isSystem: isSystem))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.body
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if isOwn {
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    @ViewBuilder
    private func bubbleBackground(isSystem: Bool) -> some View {
        if isSystem {
            Color.ccPrimary.opacity(0.10)
        } else if isOwn {
            LinearGradient(
                colors: [Color.ccPrimary, Color.ccPrimary.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.ccSurface
        }
    }

    private var avatar: some View {
        let initials = String(
            message.authorDisplayName
                .split(separator: " ")
                .prefix(2)
                .compactMap(\.first)
        ).uppercased()
        let displayInitials = initials.isEmpty ? "?" : initials
        return ZStack {
            SwiftUI.Circle()
                .fill(Color.ccPrimary.opacity(0.18))
                .frame(width: 30, height: 30)
            if message.authorAvatarEmoji.isEmpty {
                Text(displayInitials)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ccPrimary)
            } else {
                Text(message.authorAvatarEmoji)
                    .font(.system(size: 16))
            }
        }
    }
}
