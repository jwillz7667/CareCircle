import Foundation

// MARK: - AppTab

/// Identifies the four top-level tabs in `MainTabView`. Bound to the
/// `TabView`'s selection so leaf views (e.g. the Today dashboard) can
/// programmatically switch tabs — the Today screen uses this to route
/// "See all" affordances over to Meds or Brain.
enum AppTab: Hashable {
    /// Synthesis surface. Composes signals from Meds + Pulse + Brain.
    case today
    /// Medication safety system. Interactions, escalation, refills, adherence.
    case meds
    /// Family Brain. Shared multi-author record of care.
    case brain
    /// Junk drawer: settings, history archives, secondary surfaces.
    case more
}
