import Foundation
import OSLog

// MARK: - BackendTokenStore

/// Actor that owns the cached access/refresh token pair and its durable
/// Keychain backing. Split out of `APIClient` so the transport actor can
/// stay focused on request building and retry, while this store handles
/// the lazy hydrate + write-through caching.
actor BackendTokenStore {
    private let keychain: KeychainStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var cachedTokens: BackendTokens?
    private var didLoadFromKeychain = false

    init(
        keychain: KeychainStore,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) {
        self.keychain = keychain
        self.encoder = encoder
        self.decoder = decoder
    }

    func currentTokens() -> BackendTokens? {
        if !didLoadFromKeychain {
            didLoadFromKeychain = true
            do {
                guard let data = try keychain.data(forKey: KeychainStore.backendTokensKey) else {
                    cachedTokens = nil
                    return nil
                }
                cachedTokens = try decoder.decode(BackendTokens.self, from: data)
            } catch {
                AppLogger.backend.error(
                    "Failed to load backend tokens from keychain: \(String(describing: error), privacy: .public)"
                )
                cachedTokens = nil
            }
        }
        return cachedTokens
    }

    func storeTokens(_ tokens: BackendTokens) throws(APIError) {
        do {
            let data = try encoder.encode(tokens)
            try keychain.set(data, forKey: KeychainStore.backendTokensKey)
        } catch {
            AppLogger.backend.error(
                "Failed to persist backend tokens: \(String(describing: error), privacy: .public)"
            )
            throw .refreshFailed
        }
        cachedTokens = tokens
        didLoadFromKeychain = true
    }

    func clearTokens() {
        do {
            try keychain.delete(KeychainStore.backendTokensKey)
        } catch {
            AppLogger.backend.error(
                "Failed to delete backend tokens: \(String(describing: error), privacy: .public)"
            )
        }
        cachedTokens = nil
        didLoadFromKeychain = true
    }
}
