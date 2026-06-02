import Foundation

// MARK: - VitalKind

/// Categories of vital reading the app supports in v1. Mirrors the
/// backend CHECK constraint on `vitals.kind`. Blood pressure is split
/// across two kinds so each row carries a single numeric value — the
/// UI re-pairs them on display.
///
/// Beyond the seven discrete vital signs, the enum also covers the
/// HealthKit data points that have the highest caregiving signal for
/// older adults: falls, walking steadiness, sleep, resting heart rate,
/// and daily step count. These are HealthKit-imported in v1 (manual
/// entry is exposed only for the seven base vitals).
enum VitalKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case heartRate = "heart_rate"
    case bloodPressureSystolic = "blood_pressure_systolic"
    case bloodPressureDiastolic = "blood_pressure_diastolic"
    case bodyWeight = "body_weight"
    case bloodGlucose = "blood_glucose"
    case oxygenSaturation = "oxygen_saturation"
    case bodyTemperature = "body_temperature"
    case respiratoryRate = "respiratory_rate"
    case falls
    case walkingSteadiness = "walking_steadiness"
    case sleepHours = "sleep_hours"
    case restingHeartRate = "resting_heart_rate"
    case stepCount = "step_count"

    var id: String {
        rawValue
    }

    /// Kinds the user can manually enter from the Add Vital sheet.
    /// HealthKit-only kinds (falls, walking steadiness, sleep, resting
    /// HR, steps) are imported automatically and hidden from manual
    /// entry to avoid double-counting.
    static var manualEntryKinds: [VitalKind] {
        [
            .heartRate,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .bodyWeight,
            .bloodGlucose,
            .oxygenSaturation,
            .bodyTemperature,
            .respiratoryRate,
        ]
    }

    var isManuallyEnterable: Bool {
        VitalKind.manualEntryKinds.contains(self)
    }

    var displayName: String {
        switch self {
        case .heartRate: "Heart rate"
        case .bloodPressureSystolic: "Blood pressure (systolic)"
        case .bloodPressureDiastolic: "Blood pressure (diastolic)"
        case .bodyWeight: "Weight"
        case .bloodGlucose: "Blood glucose"
        case .oxygenSaturation: "Oxygen saturation"
        case .bodyTemperature: "Body temperature"
        case .respiratoryRate: "Respiratory rate"
        case .falls: "Fall events"
        case .walkingSteadiness: "Walking steadiness"
        case .sleepHours: "Sleep"
        case .restingHeartRate: "Resting heart rate"
        case .stepCount: "Steps"
        }
    }

    /// Short label used in compact rows and chips.
    var shortName: String {
        switch self {
        case .heartRate: "HR"
        case .bloodPressureSystolic: "BP (sys)"
        case .bloodPressureDiastolic: "BP (dia)"
        case .bodyWeight: "Weight"
        case .bloodGlucose: "Glucose"
        case .oxygenSaturation: "SpO₂"
        case .bodyTemperature: "Temp"
        case .respiratoryRate: "RR"
        case .falls: "Falls"
        case .walkingSteadiness: "Walking"
        case .sleepHours: "Sleep"
        case .restingHeartRate: "Rest HR"
        case .stepCount: "Steps"
        }
    }

    var systemImageName: String {
        switch self {
        case .heartRate: "heart.fill"
        case .bloodPressureSystolic, .bloodPressureDiastolic: "waveform.path.ecg"
        case .bodyWeight: "scalemass.fill"
        case .bloodGlucose: "drop.fill"
        case .oxygenSaturation: "lungs.fill"
        case .bodyTemperature: "thermometer.medium"
        case .respiratoryRate: "wind"
        case .falls: "figure.fall"
        case .walkingSteadiness: "figure.walk.motion"
        case .sleepHours: "bed.double.fill"
        case .restingHeartRate: "heart.text.square"
        case .stepCount: "figure.walk"
        }
    }

    /// Suggested SI / US unit for new manual entry or HK import. The
    /// user can change it for manual entries; HK imports always use
    /// the canonical unit listed here.
    var defaultUnit: String {
        switch self {
        case .heartRate, .restingHeartRate: "bpm"
        case .bloodPressureSystolic, .bloodPressureDiastolic: "mmHg"
        case .bodyWeight: "lb"
        case .bloodGlucose: "mg/dL"
        case .oxygenSaturation: "%"
        case .bodyTemperature: "°F"
        case .respiratoryRate: "breaths/min"
        case .falls: "count"
        case .walkingSteadiness: "%"
        case .sleepHours: "hours"
        case .stepCount: "steps"
        }
    }

    /// Reasonable input range for client-side sanity check on manual
    /// entry. Outside-range values prompt a "double check this" hint
    /// but are still accepted. HK-only kinds use generous bounds since
    /// HK is the only writer.
    var sanityRange: ClosedRange<Double> {
        switch self {
        case .heartRate, .restingHeartRate: 20 ... 250
        case .bloodPressureSystolic: 60 ... 250
        case .bloodPressureDiastolic: 30 ... 150
        case .bodyWeight: 30 ... 600
        case .bloodGlucose: 20 ... 600
        case .oxygenSaturation, .walkingSteadiness: 0 ... 100
        case .bodyTemperature: 90 ... 110
        case .respiratoryRate: 4 ... 60
        case .falls: 0 ... 100
        case .sleepHours: 0 ... 24
        case .stepCount: 0 ... 100_000
        }
    }
}

// MARK: - VitalSource

enum VitalSource: String, CaseIterable, Codable, Sendable {
    case manual
    case healthkit

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .healthkit: "Health (Apple)"
        }
    }

    var systemImageName: String {
        switch self {
        case .manual: "person.fill"
        case .healthkit: "heart.text.square.fill"
        }
    }
}
