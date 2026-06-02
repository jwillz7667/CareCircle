import SwiftUI

// MARK: - VitalKind tint

/// UI-layer color mapping for `VitalKind`. Lives in the design system rather
/// than on the domain enum so `Models/VitalKind.swift` stays free of SwiftUI
/// and the inward-only dependency direction holds. Keys into SageTheme.
extension VitalKind {
    var tintColor: Color {
        switch self {
        case .heartRate,
             .bloodPressureSystolic,
             .bloodPressureDiastolic,
             .bodyTemperature,
             .falls,
             .restingHeartRate:
            Color.ccDanger
        case .bodyWeight, .bloodGlucose, .respiratoryRate, .stepCount, .walkingSteadiness:
            Color.ccPrimary
        case .oxygenSaturation, .sleepHours:
            Color.ccSecondary
        }
    }
}
