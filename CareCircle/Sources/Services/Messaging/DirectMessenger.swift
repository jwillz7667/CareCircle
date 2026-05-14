import Foundation
import OSLog
import SwiftData

// MARK: - DirectMessenger

/// Thin orchestration layer for encrypted 1-on-1 messages inside a
/// Circle. Wraps `DocumentVault` (the per-Circle AES-GCM key store) so
/// the view layer doesn't have to know about CryptoKit, and centralises
/// the "find or create thread" logic that both the list view and the
/// composer rely on.
@Observable
@MainActor
final class DirectMessenger {
    private let vault: DocumentVault

    init(vault: DocumentVault = .shared) {
        self.vault = vault
    }

    enum SendError: LocalizedError {
        case empty
        case noCircleKey
        case seal(String)
        case persistence(String)

        var errorDescription: String? {
            switch self {
            case .empty: "Type a message first."
            case .noCircleKey:
                "Awaiting Circle key from the primary caregiver. Try again in a moment."
            case let .seal(message): "Couldn't encrypt the message: \(message)"
            case let .persistence(message): "Couldn't save the message: \(message)"
            }
        }
    }

    func threadsForCircle(_ circle: Circle) -> [DirectThread] {
        circle.directThreads.sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// Returns the existing thread between these two participants in the
    /// Circle, or creates a fresh row and returns it.
    @discardableResult
    func openOrCreateThread(
        between selfID: String,
        selfName: String,
        and otherID: String,
        otherName: String,
        in circle: Circle,
        modelContext: ModelContext
    ) -> DirectThread {
        let dedupe = DirectThread.dedupeKey(participantAppleUserIDs: [selfID, otherID])
        if let existing = circle.directThreads.first(where: { $0.participantAppleUserIDsRaw == dedupe }) {
            return existing
        }
        let thread = DirectThread(
            circle: circle,
            participantAppleUserIDs: [selfID, otherID],
            participantDisplayNames: [selfName, otherName]
        )
        modelContext.insert(thread)
        return thread
    }

    @discardableResult
    func send(
        body: String,
        in thread: DirectThread,
        from sender: ActivityAuthorContext,
        circle: Circle,
        modelContext: ModelContext
    ) throws -> DirectMessage {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SendError.empty }
        let payload = try sealBody(
            trimmed,
            senderID: sender.appleUserID,
            ownerID: circle.ownerAppleUserID,
            circleID: circle.id
        )
        let message = DirectMessage(
            thread: thread,
            senderAppleUserID: sender.appleUserID,
            senderDisplayName: sender.displayName,
            bodyCiphertext: payload.ciphertext,
            bodyNonce: payload.nonce,
            bodyTag: payload.tag
        )
        modelContext.insert(message)
        thread.lastMessageAt = .now
        do {
            try modelContext.save()
        } catch {
            throw SendError.persistence(error.localizedDescription)
        }
        return message
    }

    func openBody(_ message: DirectMessage, in circleID: UUID) -> String {
        let payload = DocumentVault.SealedPayload(
            ciphertext: message.bodyCiphertext,
            nonce: message.bodyNonce,
            tag: message.bodyTag
        )
        do {
            let plain = try vault.open(payload: payload, circleID: circleID)
            return String(data: plain, encoding: .utf8) ?? ""
        } catch {
            AppLogger.persistence.error(
                "DM open failed: \(String(describing: error), privacy: .public)"
            )
            return ""
        }
    }

    /// Returns the most-recent body preview for the thread, or nil if it
    /// can't be decrypted yet (e.g. missing key envelope on this device).
    func latestPreview(for thread: DirectThread, circleID: UUID) -> String? {
        guard let last = thread.messages.max(by: { $0.sentAt < $1.sentAt }) else {
            return nil
        }
        let plain = openBody(last, in: circleID)
        return plain.isEmpty ? nil : plain
    }

    private func sealBody(
        _ body: String,
        senderID: String,
        ownerID: String,
        circleID: UUID
    ) throws -> DocumentVault.SealedPayload {
        let data = Data(body.utf8)
        do {
            if senderID == ownerID {
                return try vault.sealForOwner(plaintext: data, circleID: circleID)
            }
            return try vault.sealForMember(plaintext: data, circleID: circleID)
        } catch let error as DocumentVault.VaultError {
            switch error {
            case .keyUnavailable: throw SendError.noCircleKey
            case let .sealFailure(message), let .openFailure(message): throw SendError.seal(message)
            case let .keychain(keychainError):
                throw SendError.seal(keychainError.errorDescription ?? "Keychain error")
            }
        }
    }
}
