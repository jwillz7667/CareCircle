import OSLog
import SwiftData
import SwiftUI

// MARK: - DirectThreadDetailView

/// Encrypted 1-on-1 chat inside a Circle. Bubbles decrypt the body
/// on render via `DirectMessenger.openBody(_:in:)`; the composer at the
/// bottom seals each outgoing message with the per-Circle AES-256 key
/// before persisting.
struct DirectThreadDetailView: View {
    let thread: DirectThread
    let circle: Circle
    let viewerAppleUserID: String
    let viewerDisplayName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(DirectMessenger.self) private var messenger
    @State private var composedText = ""
    @State private var sendError: String?

    private var orderedMessages: [DirectMessage] {
        thread.messages.sorted { $0.sentAt < $1.sentAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            encryptionBanner
            if orderedMessages.isEmpty {
                emptyState
            } else {
                stream
            }
            if let sendError {
                Text(sendError)
                    .font(.footnote)
                    .foregroundStyle(Color.ccDanger)
                    .padding(.horizontal, Theme.spacing)
            }
            composer
        }
        .background(Color.ccBackground)
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
    }

    private var headerTitle: String {
        let ids = thread.participantAppleUserIDs
        let names = thread.participantDisplayNames
        guard ids.count == names.count else { return names.first ?? "Direct message" }
        for (id, name) in zip(ids, names) where id != viewerAppleUserID {
            return name
        }
        return "Direct message"
    }

    private var encryptionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Color.ccPrimary)
            Text("End-to-end encrypted with the Circle's key.")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.ccSecondary)
            Spacer()
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 6)
        .background(Color.ccPrimary.opacity(0.08))
    }

    private var stream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(orderedMessages) { message in
                        bubble(message)
                            .id(message.id)
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary.opacity(0.7))
            Text("Say hi to start this thread.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func bubble(_ message: DirectMessage) -> some View {
        let isOwn = message.senderAppleUserID == viewerAppleUserID
        let body = messenger.openBody(message, in: circle.id)
        return HStack(alignment: .bottom, spacing: 4) {
            if isOwn { Spacer(minLength: 40) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                bubbleBody(body, isOwn: isOwn)
                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.ccSecondary)
                    .padding(.horizontal, 4)
            }
            if !isOwn { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }

    private func bubbleBody(_ body: String, isOwn: Bool) -> some View {
        Text(body.isEmpty ? "🔒 (locked — awaiting key)" : body)
            .font(.body)
            .foregroundStyle(isOwn ? Color.white : Color.ccText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                bubbleBackground(isOwn: isOwn)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)
            .contextMenu {
                if !body.isEmpty {
                    Button {
                        UIPasteboard.general.string = body
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
    }

    @ViewBuilder
    private func bubbleBackground(isOwn: Bool) -> some View {
        if isOwn {
            LinearGradient(
                colors: [Color.ccPrimary, Color.ccPrimary.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.ccSurface
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Encrypted message…", text: $composedText, axis: .vertical)
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
                            canSend ? Color.ccPrimary : Color.ccPrimary.opacity(0.35),
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
    }

    private func send() {
        let sender = ActivityAuthorContext(
            appleUserID: viewerAppleUserID,
            displayName: viewerDisplayName
        )
        do {
            _ = try messenger.send(
                body: composedText,
                in: thread,
                from: sender,
                circle: circle,
                modelContext: modelContext
            )
            composedText = ""
            sendError = nil
        } catch let error as DirectMessenger.SendError {
            sendError = error.errorDescription
            AppLogger.app.error(
                "DM send failed: \(String(describing: error), privacy: .public)"
            )
        } catch {
            sendError = "Couldn't send. Try again."
            AppLogger.app.error(
                "DM send failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        guard let last = orderedMessages.last else { return }
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
