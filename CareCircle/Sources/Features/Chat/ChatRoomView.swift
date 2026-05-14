import OSLog
import SwiftData
import SwiftUI

// MARK: - ChatRoomView

/// Circle Wall — everyone in the Circle reads the same chronological
/// stream of posts. Compose at the bottom, taps shoot up as fresh
/// bubbles, and CloudKit's shared zone fans the rows out to every
/// other member of the Circle. No DMs in v1; the wall is intentionally
/// communal so coordination notes ("Picked up Mom from PT — she's
/// tired") are visible to everyone instead of fragmented across
/// pairwise threads.
struct ChatRoomView: View {
    let authState: AuthState

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Circle.createdAt) private var circles: [Circle]
    @State private var composedText = ""
    @State private var pinnedMessageID: UUID?

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id }) ?? circles.first
    }

    private var author: ActivityAuthorContext? {
        guard case let .signedIn(user) = authState.status else { return nil }
        return ActivityAuthorContext(appleUserID: user.id, displayName: user.displayName)
    }

    private var orderedMessages: [ChatMessage] {
        guard let circle = activeCircle else { return [] }
        return circle.chatMessages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if orderedMessages.isEmpty {
                    emptyState
                } else {
                    messageStream
                }
                composer
            }
            .background(Color.ccBackground)
            .navigationTitle("Wall")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.ccPrimary.opacity(0.7))
            Text("Nothing on the Wall yet.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Text("Drop the first update — everyone in the Circle will see it.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacing * 2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var messageStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(groupedByDay, id: \.0) { day, messages in
                        Section {
                            ForEach(messages) { message in
                                bubble(message)
                                    .id(message.id)
                            }
                        } header: {
                            dayHeader(day)
                        }
                    }
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
            }
            .onAppear { scrollToBottom(proxy: proxy, animated: false) }
            .onChange(of: orderedMessages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
        }
    }

    private var groupedByDay: [(Date, [ChatMessage])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: orderedMessages) { message in
            calendar.startOfDay(for: message.createdAt)
        }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    private func dayHeader(_ day: Date) -> some View {
        Text(VitalFormatting.relativeRecordedAt(day))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ccSecondary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Color.ccSurface.opacity(0.9), in: Capsule())
            .frame(maxWidth: .infinity)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isOwn = (author?.appleUserID ?? "") == message.authorAppleUserID
        return HStack(alignment: .bottom, spacing: 8) {
            if !isOwn {
                authorAvatar(message)
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
                bubbleBody(message, isOwn: isOwn)
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ccSecondary)
                    .padding(.horizontal, 4)
            }
            if isOwn {
                authorAvatar(message)
            } else {
                Spacer(minLength: 32)
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    private func bubbleBody(_ message: ChatMessage, isOwn: Bool) -> some View {
        let isSystem = message.kind == .system
        return Text(message.body)
            .font(.body)
            .foregroundStyle(isSystem ? Color.ccPrimary : (isOwn ? Color.white : Color.ccText))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                bubbleBackground(isOwn: isOwn, isSystem: isSystem)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.body
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if isOwn {
                    Button(role: .destructive) {
                        delete(message)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    @ViewBuilder
    private func bubbleBackground(isOwn: Bool, isSystem: Bool) -> some View {
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

    private func authorAvatar(_ message: ChatMessage) -> some View {
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

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Share something with the Circle…", text: $composedText, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.ccSurface, in: RoundedRectangle(cornerRadius: 18))
                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            canSend
                                ? Color.ccPrimary
                                : Color.ccPrimary.opacity(0.35),
                            in: SwiftUI.Circle()
                        )
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 10)
            .background(Color.ccBackground)
        }
    }

    private var canSend: Bool {
        !composedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && activeCircle != nil
            && author?.hasIdentity == true
    }

    private func send() {
        guard let circle = activeCircle, let author else { return }
        let trimmed = composedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let message = ChatMessage(
            authorAppleUserID: author.appleUserID,
            authorDisplayName: author.displayName,
            body: trimmed,
            kind: .wall
        )
        message.circle = circle
        modelContext.insert(message)
        do {
            try modelContext.save()
            composedText = ""
        } catch {
            AppLogger.app.error(
                "Failed to save ChatMessage: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func delete(_ message: ChatMessage) {
        modelContext.delete(message)
        do {
            try modelContext.save()
        } catch {
            AppLogger.app.error(
                "Failed to delete ChatMessage: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = orderedMessages.last else { return }
        let target = last.id
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}
