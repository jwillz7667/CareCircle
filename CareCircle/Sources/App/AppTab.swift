import Foundation

// MARK: - AppTab

/// Identifies the five top-level tabs in `MainTabView`. Bound to the
/// `TabView`'s selection so leaf views (e.g. the Home dashboard) can
/// programmatically switch tabs — used by the Vitals quickview bar on
/// Home to jump straight into the Pulse tab.
enum AppTab: Hashable {
    case home
    case vitals
    case meds
    case wall
    case more
}
