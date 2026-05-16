import SwiftUI
import UIKit

/// Semantic haptic taxonomy. Use one of these — never raw
/// `UIImpactFeedbackGenerator` calls — so the app's haptic language
/// stays consistent and tunable from one place.
///
/// Mapping:
/// - `.selection` — tab switch, picker change, filter toggle
/// - `.tap` — card tap, row tap, light affordance
/// - `.confirm` — primary CTA tap (Save, Confirm)
/// - `.success` — dose taken, vital logged, note saved
/// - `.warning` — about to cancel unsaved work, destructive confirm
/// - `.failure` — save failed, network error
///
/// Never trigger haptics during background updates or on app launch —
/// only in response to direct user action.
enum Haptic {
    case selection
    case tap
    case confirm
    case success
    case warning
    case failure

    @MainActor
    func play() {
        switch self {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .tap:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .confirm:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// SwiftUI bridge for use with `.sensoryFeedback(_:trigger:)`.
    var sensory: SensoryFeedback {
        switch self {
        case .selection: .selection
        case .tap: .impact(weight: .light)
        case .confirm: .impact(weight: .medium)
        case .success: .success
        case .warning: .warning
        case .failure: .error
        }
    }
}

extension View {
    /// `.haptic(.success, trigger: doseCount)` — fires the semantic
    /// haptic whenever `trigger` changes. Wraps `.sensoryFeedback`
    /// so call sites read in app-domain language, not UIKit.
    func haptic(_ haptic: Haptic, trigger: some Equatable) -> some View {
        sensoryFeedback(haptic.sensory, trigger: trigger)
    }
}
