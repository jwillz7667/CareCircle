import Foundation
import SwiftData

// MARK: - LocationSnapshot

/// Latest known location for a single Circle member. We keep a single
/// row per `(circle, memberAppleUserID)` and overwrite in place rather
/// than appending — the Pulse map needs "where are they now," not a
/// breadcrumb trail. CloudKit's shared zone propagates the row to
/// every other member of the Circle so caregivers see each other's
/// locations on the same map.
///
/// Privacy: writes happen only when the member toggles
/// `LocationSharingService.shareLocation = true`. The toggle is
/// device-local — turning it off on this phone stops further upserts
/// but leaves the last snapshot in the shared zone (the row is
/// expected to be stale on the receiving side until the next share).
@Model
final class LocationSnapshot {
    var id = UUID()
    var memberAppleUserID = ""
    var memberDisplayName = ""
    /// Stored as Double pair rather than `CLLocationCoordinate2D` so
    /// CloudKit's `CKRecord` mapping has no opaque type to figure out.
    var latitude: Double = 0
    var longitude: Double = 0
    /// Horizontal accuracy in meters from CoreLocation; -1 if invalid.
    var accuracyMeters: Double = -1
    var altitudeMeters: Double = 0
    /// Speed in meters per second. -1 = unknown.
    var speedMPS: Double = -1
    /// Course over ground in degrees from true north. -1 = unknown.
    var courseDegrees: Double = -1
    var recordedAt = Date.now
    /// Set to `false` when the device pauses sharing — the row stays
    /// for context but the map UI greys it out and flags "paused".
    var isSharingEnabled = true

    var circle: Circle?

    init(
        id: UUID = UUID(),
        memberAppleUserID: String,
        memberDisplayName: String,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        altitudeMeters: Double,
        speedMPS: Double,
        courseDegrees: Double,
        recordedAt: Date = .now,
        isSharingEnabled: Bool = true
    ) {
        self.id = id
        self.memberAppleUserID = memberAppleUserID
        self.memberDisplayName = memberDisplayName
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.altitudeMeters = altitudeMeters
        self.speedMPS = speedMPS
        self.courseDegrees = courseDegrees
        self.recordedAt = recordedAt
        self.isSharingEnabled = isSharingEnabled
    }
}
