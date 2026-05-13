import CryptoKit
import Foundation
import OSLog

// MARK: - DocumentVault

/// Encrypts and decrypts document plaintext for a given circle. Pulls the
/// circle's symmetric key from `DocumentKeyStore` (provisioning it on the
/// first call). All operations return typed errors so the UI can surface
/// "key missing" vs "tampered ciphertext" distinctly.
nonisolated final class DocumentVault: Sendable {
    static let shared = DocumentVault()

    private let keyStore: DocumentKeyStore

    init(keyStore: DocumentKeyStore = .shared) {
        self.keyStore = keyStore
    }

    enum VaultError: LocalizedError {
        case keyUnavailable
        case sealFailure(String)
        case openFailure(String)
        case keychain(DocumentKeyStore.KeyStoreError)

        var errorDescription: String? {
            switch self {
            case .keyUnavailable:
                "Ask the Circle's primary caregiver to re-share so this device can decrypt documents."
            case let .sealFailure(message):
                "Couldn't encrypt the document: \(message)"
            case let .openFailure(message):
                "Couldn't decrypt the document: \(message)"
            case let .keychain(error):
                error.errorDescription ?? "Keychain error"
            }
        }
    }

    struct SealedPayload: Sendable, Equatable {
        let ciphertext: Data
        let nonce: Data
        let tag: Data
    }

    func sealForOwner(plaintext: Data, circleID: UUID) throws -> SealedPayload {
        let key: SymmetricKey
        do {
            key = try keyStore.provisionKey(circleID: circleID)
        } catch let error as DocumentKeyStore.KeyStoreError {
            throw VaultError.keychain(error)
        }
        return try seal(plaintext: plaintext, key: key)
    }

    func sealForMember(plaintext: Data, circleID: UUID) throws -> SealedPayload {
        let key: SymmetricKey
        do {
            guard let existing = try keyStore.loadKey(circleID: circleID) else {
                throw VaultError.keyUnavailable
            }
            key = existing
        } catch let error as DocumentKeyStore.KeyStoreError {
            throw VaultError.keychain(error)
        }
        return try seal(plaintext: plaintext, key: key)
    }

    func open(payload: SealedPayload, circleID: UUID) throws -> Data {
        let key: SymmetricKey
        do {
            guard let existing = try keyStore.loadKey(circleID: circleID) else {
                throw VaultError.keyUnavailable
            }
            key = existing
        } catch let error as DocumentKeyStore.KeyStoreError {
            throw VaultError.keychain(error)
        }
        do {
            let nonce = try AES.GCM.Nonce(data: payload.nonce)
            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: payload.ciphertext,
                tag: payload.tag
            )
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            AppLogger.persistence.error(
                "Document open failed: \(String(describing: error), privacy: .public)"
            )
            throw VaultError.openFailure(error.localizedDescription)
        }
    }

    func keyExists(circleID: UUID) -> Bool {
        (try? keyStore.loadKey(circleID: circleID)) != nil
    }

    private func seal(plaintext: Data, key: SymmetricKey) throws -> SealedPayload {
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            return SealedPayload(
                ciphertext: sealed.ciphertext,
                nonce: Data(sealed.nonce),
                tag: sealed.tag
            )
        } catch {
            AppLogger.persistence.error(
                "Document seal failed: \(String(describing: error), privacy: .public)"
            )
            throw VaultError.sealFailure(error.localizedDescription)
        }
    }
}
