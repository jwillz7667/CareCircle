import Foundation

// MARK: - ActivityType

enum ActivityType: String, Codable, CaseIterable, Sendable, Equatable {
    case textNote = "text_note"
    case photo
    case voiceNote = "voice_note"
    case medTaken = "med_taken"
    case visit
    case appointment
    case alert
    case system

    var displayName: String {
        switch self {
        case .textNote: "Note"
        case .photo: "Photo"
        case .voiceNote: "Voice note"
        case .medTaken: "Medication"
        case .visit: "Visit"
        case .appointment: "Appointment"
        case .alert: "Alert"
        case .system: "System"
        }
    }

    var systemImageName: String {
        switch self {
        case .textNote: "text.bubble.fill"
        case .photo: "photo.fill"
        case .voiceNote: "mic.fill"
        case .medTaken: "pills.fill"
        case .visit: "figure.walk"
        case .appointment: "calendar"
        case .alert: "exclamationmark.triangle.fill"
        case .system: "gearshape.fill"
        }
    }
}
