import Foundation
import Observation

// MARK: - SimplifiedModePreference

/// Stores a manual "always show simplified mode" override. Independent
/// of `Member.role` — a caregiver can flip this on to hand the phone
/// to the care recipient even if they aren't signed in as the recipient.
@Observable
final class SimplifiedModePreference {
    private let defaults: UserDefaults
    private let storageKey = "simplifiedMode.manualOverride.v1"

    var isManualOverrideEnabled: Bool {
        didSet {
            guard oldValue != isManualOverrideEnabled else { return }
            defaults.set(isManualOverrideEnabled, forKey: storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isManualOverrideEnabled = defaults.bool(forKey: storageKey)
    }

    /// Simplified mode applies when either the manual override is on or
    /// the viewer's circle role indicates they are the care recipient.
    func effectiveIsActive(viewerRole: MemberRole?) -> Bool {
        if isManualOverrideEnabled { return true }
        return viewerRole == .careRecipient
    }
}
