import Foundation

// MARK: - BackendConfiguration

/// Resolves the runtime backend URL. Reads `APIBaseURL` from the bundle's
/// `Info.plist`; the build embeds the Railway production URL there so a
/// fresh install talks to prod by default. Override via the Info-plist key
/// for staging or local development.
nonisolated struct BackendConfiguration: Sendable {
    let baseURL: URL

    static func resolveFromBundle(_ bundle: Bundle = .main) -> BackendConfiguration {
        let raw = bundle.object(forInfoDictionaryKey: "APIBaseURL") as? String
        guard let raw, let url = URL(string: raw) else {
            assertionFailure("APIBaseURL missing or malformed in Info.plist")
            // Fail-soft to the prod URL so misconfigured builds still work in TestFlight.
            return BackendConfiguration(baseURL: productionFallbackURL)
        }
        return BackendConfiguration(baseURL: url)
    }

    private static let productionFallbackURL: URL = {
        guard let url = URL(string: "https://carecircle-production-5669.up.railway.app") else {
            preconditionFailure("Production fallback URL literal is malformed.")
        }
        return url
    }()
}
