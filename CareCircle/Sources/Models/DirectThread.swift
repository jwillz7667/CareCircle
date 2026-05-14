import Foundation
import SwiftData

// MARK: - DirectThread

/// 1-on-1 private conversation between two members of a Circle. Threads
/// are scoped to the Circle (a member can only DM other members of the
/// same Circle) and identified by the sorted pair of Apple user IDs so
/// the participants resolve to the same row on both devices.
///
/// **Encryption.** Bodies are stored inside `DirectMessage` as AES-GCM
/// ciphertext sealed with the per-Circle symmetric key
/// (`DocumentKeyStore`). The thread row itself holds only routing data
/// (sorted participant IDs, snapshotted display names, last-message
/// timestamp) — preview text is computed on the fly by decrypting the
/// most recent message at render time.
@Model
final class DirectThread {
    var id = UUID()
    var circle: Circle?

    /// Sorted, comma-joined Apple user IDs. Two-party only in v1, so
    /// always exactly two IDs. Used as the dedupe key when opening a
    /// conversation with someone.
    var participantAppleUserIDsRaw = ""

    /// Sorted, comma-joined display names — snapshotted from `Member`
    /// records at thread creation so the list view stays stable even if
    /// a member is renamed/removed later.
    var participantDisplayNamesRaw = ""

    var createdAt = Date.now
    var lastMessageAt = Date.now

    @Relationship(deleteRule: .cascade, inverse: \DirectMessage.thread)
    var messagesStore: [DirectMessage]?

    var messages: [DirectMessage] {
        get { messagesStore ?? [] }
        set { messagesStore = newValue }
    }

    var participantAppleUserIDs: [String] {
        participantAppleUserIDsRaw
            .split(separator: ",")
            .map(String.init)
    }

    var participantDisplayNames: [String] {
        participantDisplayNamesRaw
            .split(separator: ",")
            .map(String.init)
    }

    init(
        id: UUID = UUID(),
        circle: Circle? = nil,
        participantAppleUserIDs: [String],
        participantDisplayNames: [String],
        createdAt: Date = .now,
        lastMessageAt: Date = .now
    ) {
        self.id = id
        self.circle = circle
        let sortedIDs = participantAppleUserIDs.sorted()
        let sortedNames = sortedIDs.compactMap { id in
            zip(participantAppleUserIDs, participantDisplayNames)
                .first { $0.0 == id }?.1
        }
        participantAppleUserIDsRaw = sortedIDs.joined(separator: ",")
        participantDisplayNamesRaw = sortedNames.joined(separator: ",")
        self.createdAt = createdAt
        self.lastMessageAt = lastMessageAt
    }

    /// Stable lookup key for "is there already a thread between A and B?"
    static func dedupeKey(participantAppleUserIDs: [String]) -> String {
        participantAppleUserIDs.sorted().joined(separator: ",")
    }
}
