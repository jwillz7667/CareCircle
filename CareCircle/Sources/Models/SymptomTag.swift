import Foundation

// MARK: - SymptomTag

/// Curated set of daily-life symptoms that families track for a Care
/// Recipient. We avoid clinical-coding (SNOMED/ICD-10) on purpose —
/// caregivers describe what they observe, not what the chart says, and
/// the audience for the journal is family members not clinicians.
enum SymptomTag: String, CaseIterable, Sendable, Identifiable {
    case pain
    case fatigue
    case nausea
    case dizziness
    case confusion
    case shortnessOfBreath
    case headache
    case anxiety
    case poorAppetite
    case poorSleep
    case swelling
    case fever
    case cough
    case constipation

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .pain: "Pain"
        case .fatigue: "Fatigue"
        case .nausea: "Nausea"
        case .dizziness: "Dizziness"
        case .confusion: "Confusion"
        case .shortnessOfBreath: "Short of breath"
        case .headache: "Headache"
        case .anxiety: "Anxiety"
        case .poorAppetite: "Poor appetite"
        case .poorSleep: "Poor sleep"
        case .swelling: "Swelling"
        case .fever: "Fever"
        case .cough: "Cough"
        case .constipation: "Constipation"
        }
    }

    var systemImageName: String {
        switch self {
        case .pain: "bolt.fill"
        case .fatigue: "bed.double.fill"
        case .nausea: "drop.fill"
        case .dizziness: "tornado"
        case .confusion: "questionmark.bubble.fill"
        case .shortnessOfBreath: "wind"
        case .headache: "brain.head.profile"
        case .anxiety: "waveform.path.ecg"
        case .poorAppetite: "fork.knife"
        case .poorSleep: "moon.zzz.fill"
        case .swelling: "circle.dashed.inset.filled"
        case .fever: "thermometer.high"
        case .cough: "lungs.fill"
        case .constipation: "stomach"
        }
    }
}
