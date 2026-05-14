import Foundation

// MARK: - Mood

/// Five-step Likert scale for a daily mood log. Stored as an `Int`
/// (`1`…`5`) so SwiftData + CloudKit don't have to migrate enum cases
/// when we add new copy in the UI.
///
/// `1` = "really struggling", `5` = "doing well". The midpoint (`3`) is
/// neutral. Emoji + description are computed for UI affordance only —
/// they aren't stored.
enum Mood: Int, CaseIterable, Sendable, Identifiable {
    case veryLow = 1
    case low = 2
    case neutral = 3
    case good = 4
    case great = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .veryLow: "😣"
        case .low: "😔"
        case .neutral: "😐"
        case .good: "🙂"
        case .great: "😊"
        }
    }

    var label: String {
        switch self {
        case .veryLow: "Struggling"
        case .low: "Low"
        case .neutral: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }
}
