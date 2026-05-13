import Foundation
import Security

// MARK: - KeychainStore

nonisolated struct KeychainStore: Sendable {
    let service: String

    static let defaultService = "Res.CareCircle.auth"

    /// Key for the persisted `SignedInUser` payload.
    static let signedInUserKey = "signed-in-user"

    /// Backend session tokens — minted by `POST /v1/auth/apple` and
    /// rotated through `POST /v1/auth/refresh`. Stored as JSON.
    static let backendTokensKey = "backend-tokens"

    init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    func set(_ data: Data, forKey key: String) throws(KeychainError) {
        let query = baseQuery(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw .unhandled(updateStatus)
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw .unhandled(addStatus)
        }
    }

    func data(forKey key: String) throws(KeychainError) -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw .unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw .unhandled(status)
        }
    }

    func delete(_ key: String) throws(KeychainError) {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw .unhandled(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
