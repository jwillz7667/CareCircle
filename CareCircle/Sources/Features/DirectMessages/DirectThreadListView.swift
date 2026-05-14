import SwiftData
import SwiftUI

// MARK: - DirectThreadListView

/// Inbox of 1-on-1 encrypted conversations inside the active Circle.
/// Sorted by most-recent activity, with a "New message" toolbar item
/// that lets the caregiver pick any other Circle member to message.
///
/// **Encryption.** Every body is sealed with the per-Circle AES-256 key
/// from `DocumentKeyStore` — same key that protects sensitive documents.
/// The list view decrypts the most-recent message in each thread on
/// render to show a preview; bodies never appear in plaintext on disk.
struct DirectThreadListView: View {
    let circle: Circle
    let viewerAppleUserID: String
    let viewerDisplayName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(DirectMessenger.self) private var messenger
    @State private var isPickingRecipient = false
    @State private var openingThread: DirectThread?

    private var threads: [DirectThread] {
        messenger.threadsForCircle(circle)
    }

    var body: some View {
        Group {
            if threads.isEmpty {
                emptyState
            } else {
                threadList
            }
        }
        .background(Color.ccBackground)
        .navigationTitle("Direct Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPickingRecipient = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .accessibilityLabel("New message")
                }
            }
        }
        .sheet(isPresented: $isPickingRecipient) {
            NavigationStack {
                DirectRecipientPicker(
                    circle: circle,
                    viewerAppleUserID: viewerAppleUserID
                ) { member in
                    isPickingRecipient = false
                    let thread = messenger.openOrCreateThread(
                        between: viewerAppleUserID,
                        selfName: viewerDisplayName,
                        and: member.appleUserID,
                        otherName: member.displayName.isEmpty ? "Member" : member.displayName,
                        in: circle,
                        modelContext: modelContext
                    )
                    openingThread = thread
                }
            }
        }
        .navigationDestination(item: $openingThread) { thread in
            DirectThreadDetailView(
                thread: thread,
                circle: circle,
                viewerAppleUserID: viewerAppleUserID,
                viewerDisplayName: viewerDisplayName
            )
        }
    }

    private var threadList: some View {
        List {
            ForEach(threads) { thread in
                NavigationLink {
                    DirectThreadDetailView(
                        thread: thread,
                        circle: circle,
                        viewerAppleUserID: viewerAppleUserID,
                        viewerDisplayName: viewerDisplayName
                    )
                } label: {
                    threadRow(thread)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "lock.bubble.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Color.ccPrimary.opacity(0.7))
            Text("Encrypted direct messages")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Text("Start a 1-on-1 with any Circle member. Bodies are sealed with the Circle's key — nothing else can read them.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacing * 2)
            Button {
                isPickingRecipient = true
            } label: {
                Label("Start a conversation", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ccPrimary)
            .padding(.horizontal, Theme.spacing * 2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.ccBackground)
    }

    private func threadRow(_ thread: DirectThread) -> some View {
        let otherName = otherParticipantName(in: thread) ?? "Member"
        let preview = messenger.latestPreview(for: thread, circleID: circle.id) ?? "Encrypted — tap to open"
        return HStack(alignment: .top, spacing: 12) {
            avatarBubble(for: otherName)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(otherName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Spacer()
                    Text(thread.lastMessageAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                Text(preview)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func avatarBubble(for name: String) -> some View {
        let initials = String(
            name.split(separator: " ").prefix(2).compactMap(\.first)
        ).uppercased()
        return ZStack {
            SwiftUI.Circle()
                .fill(Color.ccPrimary.opacity(0.18))
                .frame(width: 38, height: 38)
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.ccPrimary)
        }
    }

    private func otherParticipantName(in thread: DirectThread) -> String? {
        let ids = thread.participantAppleUserIDs
        let names = thread.participantDisplayNames
        guard ids.count == names.count else { return names.first }
        for (id, name) in zip(ids, names) where id != viewerAppleUserID {
            return name
        }
        return nil
    }
}

// MARK: - DirectRecipientPicker

private struct DirectRecipientPicker: View {
    let circle: Circle
    let viewerAppleUserID: String
    let onSelect: (Member) -> Void

    @Environment(\.dismiss) private var dismiss

    private var candidates: [Member] {
        circle.members
            .filter { $0.appleUserID != viewerAppleUserID }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        List {
            if candidates.isEmpty {
                Section {
                    Text("Invite another caregiver to your Circle to start a direct message.")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }
            } else {
                Section("Circle members") {
                    ForEach(candidates) { member in
                        Button {
                            onSelect(member)
                        } label: {
                            HStack(spacing: 12) {
                                Text(member.displayName.isEmpty ? "Member" : member.displayName)
                                    .font(.body)
                                    .foregroundStyle(Color.ccText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.ccSecondary)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle("New message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
