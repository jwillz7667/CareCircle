import Foundation

// MARK: - InsightKind

/// The class of observation an `Insight` represents. Stored as a raw
/// string so SwiftData migrations stay non-destructive when we add new
/// pattern detectors later.
nonisolated enum InsightKind: String, Codable, CaseIterable, Sendable {
    case doseTimingDrift = "dose_timing_drift"
    case missedDoseRisk = "missed_dose_risk"
    case moodTrend = "mood_trend"
    case vitalOutOfRange = "vital_out_of_range"
    case sleepDecline = "sleep_decline"

    var displayName: String {
        switch self {
        case .doseTimingDrift: "Dose timing"
        case .missedDoseRisk: "Missed doses"
        case .moodTrend: "Mood"
        case .vitalOutOfRange: "Vitals"
        case .sleepDecline: "Sleep"
        }
    }

    var systemImage: String {
        switch self {
        case .doseTimingDrift: "clock.arrow.2.circlepath"
        case .missedDoseRisk: "exclamationmark.triangle"
        case .moodTrend: "face.smiling"
        case .vitalOutOfRange: "heart.text.square"
        case .sleepDecline: "bed.double"
        }
    }
}

// MARK: - InsightSeverity

/// Severity controls sort order in the list and the tint applied to
/// the card. We deliberately keep this to three levels — a five-level
/// scale would tempt the engine into making fine-grained distinctions
/// the underlying data can't support.
nonisolated enum InsightSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case suggestion
    case warning

    var sortRank: Int {
        switch self {
        case .warning: 0
        case .suggestion: 1
        case .info: 2
        }
    }
}

// MARK: - InsightSubjectKind

/// What an insight is *about*. Used to deep-link the apply CTA — e.g.
/// a `medication` insight opens the medication detail view.
nonisolated enum InsightSubjectKind: String, Codable, CaseIterable, Sendable {
    case medication
    case careRecipient
    case vital
    case journalEntry
    case circle
}
