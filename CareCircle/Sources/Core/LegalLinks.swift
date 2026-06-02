import Foundation

// MARK: - LegalLinks

/// Resolves the legal URLs surfaced on the subscription paywall, which App
/// Store Review Guideline 3.1.2 requires for auto-renewable subscriptions.
///
/// Both values are read from `Info.plist` so they can change without a code
/// release. `TermsOfUseURL` falls back to Apple's standard EULA when unset —
/// the EULA we agree to by distributing on the App Store. `PrivacyPolicyURL`
/// has no safe default; the paywall renders the link only once it is set.
enum LegalLinks {
    /// Apple's standard end-user license agreement. Acceptable to Apple as the
    /// Terms of Use when an app ships no custom EULA.
    private static let appleStandardEULA = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )

    static var termsOfUse: URL? {
        configuredURL(forInfoKey: "TermsOfUseURL") ?? appleStandardEULA
    }

    static var privacyPolicy: URL? {
        configuredURL(forInfoKey: "PrivacyPolicyURL")
    }

    private static func configuredURL(forInfoKey key: String) -> URL? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !raw.isEmpty,
            let url = URL(string: raw) else { return nil }
        return url
    }
}
