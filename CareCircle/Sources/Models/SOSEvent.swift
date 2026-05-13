import Foundation
import SwiftData

// MARK: - SOSEvent

/// Records a single SOS trigger. Lives in the Circle's shared zone so
/// every member learns about it via the normal CloudKit sync path —
/// no custom backend, no manual fan-out. Latitude / longitude are
/// optional because the user may not have granted location, or the
/// fix may have timed out during the 30-second countdown.
@Model
final class SOSEvent {
    var id = UUID()
    var triggeredByAppleUserID = ""
    var triggeredByDisplayName = ""
    var triggeredAt = Date.now
    var latitude: Double?
    var longitude: Double?
    var locationAccuracyMeters: Double?
    var canceledAt: Date?
    var canceledByAppleUserID: String?
    var resolvedAt: Date?
    var resolvedByAppleUserID: String?
    var resolutionNotes: String?
    var primaryContactCalled = false

    var circle: Circle?

    init(
        id: UUID = UUID(),
        triggeredByAppleUserID: String,
        triggeredByDisplayName: String,
        triggeredAt: Date = .now,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationAccuracyMeters: Double? = nil
    ) {
        self.id = id
        self.triggeredByAppleUserID = triggeredByAppleUserID
        self.triggeredByDisplayName = triggeredByDisplayName
        self.triggeredAt = triggeredAt
        self.latitude = latitude
        self.longitude = longitude
        self.locationAccuracyMeters = locationAccuracyMeters
    }

    var status: SOSStatus {
        if resolvedAt != nil { return .resolved }
        if canceledAt != nil { return .canceled }
        return .active
    }

    var hasLocation: Bool {
        latitude != nil && longitude != nil
    }
}

// MARK: - SOSStatus

enum SOSStatus: String, Codable, Sendable {
    case active
    case canceled
    case resolved

    var displayName: String {
        switch self {
        case .active: "Active"
        case .canceled: "Canceled"
        case .resolved: "Resolved"
        }
    }
}
