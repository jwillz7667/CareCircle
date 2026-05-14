import Foundation
import SwiftData

// MARK: - DirectMessage

/// Single message inside a `DirectThread`. Body is stored as AES-GCM
/// ciphertext + nonce + tag — never in plaintext. Decrypt via
/// `DirectMessenger.openBody(_:in:)` which pulls the per-Circle key from
/// `DocumentKeyStore`.
@Model
final class DirectMessage {
    var id = UUID()
    var thread: DirectThread?

    /// Snapshotted at write time so the sender's name renders correctly
    /// even after they're removed from the Circle.
    var senderAppleUserID = ""
    var senderDisplayName = ""

    /// AES-GCM ciphertext of the UTF-8 message body.
    var bodyCiphertext = Data()
    /// AES-GCM 12-byte nonce.
    var bodyNonce = Data()
    /// AES-GCM 16-byte authentication tag.
    var bodyTag = Data()

    var sentAt = Date.now

    init(
        id: UUID = UUID(),
        thread: DirectThread? = nil,
        senderAppleUserID: String,
        senderDisplayName: String,
        bodyCiphertext: Data,
        bodyNonce: Data,
        bodyTag: Data,
        sentAt: Date = .now
    ) {
        self.id = id
        self.thread = thread
        self.senderAppleUserID = senderAppleUserID
        self.senderDisplayName = senderDisplayName
        self.bodyCiphertext = bodyCiphertext
        self.bodyNonce = bodyNonce
        self.bodyTag = bodyTag
        self.sentAt = sentAt
    }
}
