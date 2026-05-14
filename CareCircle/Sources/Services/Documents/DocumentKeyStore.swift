import CryptoKit
import Foundation
import OSLog
import Security

// MARK: - DocumentKeyStore

/// Per-circle symmetric key persistence in the iOS Keychain. We store the
/// raw 32 bytes of an AES-256 `SymmetricKey` under
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — device-only on
/// purpose. v1 intentionally avoids `kSecAttrSynchronizable` because raw
/// symmetric-key sync via iCloud Keychain is not yet a vetted CryptoKit
/// pattern. Future work (CKShare-sealed key envelopes) is tracked in the
/// Phase 9 plan.
nonisolated final class DocumentKeyStore: Sendable {
    static let shared = DocumentKeyStore()

    private let service: String

    init(service: String = "Res.CareCircle.documents") {
        self.service = service
    }

    enum KeyStoreError: LocalizedError {
        case keychainStatus(OSStatus, action: String)
        case unexpectedDataLength(Int)

        var errorDescription: String? {
            switch self {
            case let .keychainStatus(status, action):
                "Keychain \(action) failed (\(status))."
            case let .unexpectedDataLength(length):
                "Keychain returned an unexpected key length (\(length) bytes)."
            }
        }
    }

    func loadKey(circleID: UUID) throws -> SymmetricKey? {
        var query = baseQuery(circleID: circleID)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            guard data.count == 32 else { throw KeyStoreError.unexpectedDataLength(data.count) }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeyStoreError.keychainStatus(status, action: "load")
        }
    }

    @discardableResult
    func provisionKey(circleID: UUID) throws -> SymmetricKey {
        if let existing = try loadKey(circleID: circleID) {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }

        var attributes = baseQuery(circleID: circleID)
        attributes[kSecValueData as String] = raw
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyStoreError.keychainStatus(status, action: "add")
        }
        AppLogger.persistence.notice(
            "Provisioned document key for circle \(circleID.uuidString, privacy: .public)"
        )
        return key
    }

    /// Persists a DEK that arrived from outside this device (e.g. a
    /// CKShare-sealed envelope). No-op if a key already exists — the
    /// owner's local key is authoritative and never overwritten by an
    /// envelope pulled later on the same device.
    @discardableResult
    func persist(rawKey: Data, circleID: UUID) throws -> SymmetricKey {
        guard rawKey.count == 32 else {
            throw KeyStoreError.unexpectedDataLength(rawKey.count)
        }
        if let existing = try loadKey(circleID: circleID) {
            return existing
        }

        var attributes = baseQuery(circleID: circleID)
        attributes[kSecValueData as String] = rawKey
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyStoreError.keychainStatus(status, action: "persist")
        }
        AppLogger.persistence.notice(
            "Persisted incoming document key for circle \(circleID.uuidString, privacy: .public)"
        )
        return SymmetricKey(data: rawKey)
    }

    /// Owner-side helper: returns the raw 32 bytes of the local DEK so
    /// the sync service can stage them into a `CKRecord` envelope.
    func rawKeyBytes(circleID: UUID) throws -> Data? {
        guard let key = try loadKey(circleID: circleID) else { return nil }
        return key.withUnsafeBytes { Data($0) }
    }

    func forget(circleID: UUID) throws {
        let status = SecItemDelete(baseQuery(circleID: circleID) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeyStoreError.keychainStatus(status, action: "delete")
        }
    }

    private func baseQuery(circleID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "circle.\(circleID.uuidString).key.v1",
        ]
    }
}
