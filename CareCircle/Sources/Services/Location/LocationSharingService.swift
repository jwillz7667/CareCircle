import CoreLocation
import Foundation
import OSLog
import SwiftData

// MARK: - LocationSharingService

/// CoreLocation wrapper that publishes the current device's location
/// into the active Circle's `LocationSnapshot` row. We upsert one row
/// per `(circle, memberAppleUserID)` rather than appending — the map
/// shows "current" position, not breadcrumbs.
///
/// Authorization is "when in use" by default. Caregivers responsible
/// for someone with wandering risk can upgrade to "always" via the
/// Settings deeplink; the service notices the upgrade and starts
/// significant-change monitoring so updates continue while the app is
/// backgrounded.
///
/// Sharing is **opt-in per device**. `shareLocation = false` stops
/// upserts immediately and flips the local row's `isSharingEnabled`
/// to false so other members see "paused" rather than a stale pin.
@Observable
@MainActor
final class LocationSharingService: NSObject {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastLocation: CLLocation?
    private(set) var lastError: String?

    /// Per-circle sharing consent. A device only publishes its location into
    /// circles the member has explicitly opted into — precise coordinates are
    /// never fanned out to every circle from a single global switch.
    private(set) var enabledCircleIDs: Set<UUID>

    private let manager: CLLocationManager
    private let modelContainer: ModelContainer
    private let currentAuthor: @MainActor () -> ActivityAuthorContext?
    private static let enabledCirclesKey = "com.jwillz.carecircle.locationSharing.enabledCircles"
    private static let legacyPreferenceKey = "com.jwillz.carecircle.locationSharing.enabled"

    init(
        modelContainer: ModelContainer,
        currentAuthor: @escaping @MainActor () -> ActivityAuthorContext?,
        manager: CLLocationManager = CLLocationManager()
    ) {
        self.modelContainer = modelContainer
        self.currentAuthor = currentAuthor
        self.manager = manager
        enabledCircleIDs = Self.loadEnabledCircleIDs()
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = true
        migrateLegacyGlobalConsentIfNeeded()
        if !enabledCircleIDs.isEmpty { startUpdates() }
    }

    // MARK: - Public

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func isSharing(in circleID: UUID) -> Bool {
        enabledCircleIDs.contains(circleID)
    }

    /// Opts the current device's location sharing in or out for a single
    /// circle. Enabling ensures authorization and starts updates; disabling
    /// marks that circle's pin paused and stops the manager once no circle
    /// remains opted in.
    func setSharing(_ enabled: Bool, in circleID: UUID) {
        if enabled {
            enabledCircleIDs.insert(circleID)
        } else {
            enabledCircleIDs.remove(circleID)
        }
        persistEnabledCircleIDs()
        if enabled {
            ensureAuthorizationAndStart()
        } else {
            Task { await markPausedRow(circleID: circleID) }
            if enabledCircleIDs.isEmpty { stopUpdates() }
        }
    }

    func startUpdates() {
        guard CLLocationManager.locationServicesEnabled(), !enabledCircleIDs.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            configureBackgroundUpdates()
            manager.startUpdatingLocation()
            if manager.authorizationStatus == .authorizedAlways {
                manager.startMonitoringSignificantLocationChanges()
            }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func ensureAuthorizationAndStart() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        default:
            break
        }
    }

    /// `allowsBackgroundLocationUpdates` requires the `location`
    /// `UIBackgroundMode` (declared in Info.plist) and throws without it.
    /// Gate it on Always authorization so When-In-Use sessions don't surface
    /// the persistent blue background indicator.
    private func configureBackgroundUpdates() {
        let always = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = always
        manager.showsBackgroundLocationIndicator = always
    }

    private static func loadEnabledCircleIDs() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: enabledCirclesKey) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func persistEnabledCircleIDs() {
        UserDefaults.standard.set(enabledCircleIDs.map(\.uuidString), forKey: Self.enabledCirclesKey)
    }

    /// Migrates the pre-per-circle single global sharing bool: if it was on,
    /// seed every existing circle as opted-in once, then drop the legacy key.
    private func migrateLegacyGlobalConsentIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.legacyPreferenceKey) != nil else { return }
        if defaults.bool(forKey: Self.legacyPreferenceKey) {
            let context = ModelContext(modelContainer)
            if let circles = try? context.fetch(FetchDescriptor<Circle>()) {
                enabledCircleIDs.formUnion(circles.map(\.id))
                persistEnabledCircleIDs()
            }
        }
        defaults.removeObject(forKey: Self.legacyPreferenceKey)
    }

    // MARK: - Persistence

    private func upsertSnapshot(_ location: CLLocation) async {
        guard let author = currentAuthor() else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Circle>()
        guard let circles = try? context.fetch(descriptor), !circles.isEmpty else { return }
        let memberID = author.appleUserID
        for circle in circles where enabledCircleIDs.contains(circle.id) {
            upsert(
                in: circle,
                location: location,
                memberID: memberID,
                displayName: author.displayName,
                context: context
            )
        }
        do {
            try context.save()
        } catch {
            AppLogger.app.error(
                "Failed to persist LocationSnapshot: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func upsert(
        in circle: Circle,
        location: CLLocation,
        memberID: String,
        displayName: String,
        context: ModelContext
    ) {
        let existing = circleLocations(circle: circle, context: context)
            .first(where: { $0.memberAppleUserID == memberID })
        if let row = existing {
            row.latitude = location.coordinate.latitude
            row.longitude = location.coordinate.longitude
            row.accuracyMeters = location.horizontalAccuracy
            row.altitudeMeters = location.altitude
            row.speedMPS = location.speed
            row.courseDegrees = location.course
            row.recordedAt = location.timestamp
            row.isSharingEnabled = true
            if !displayName.isEmpty { row.memberDisplayName = displayName }
        } else {
            let row = LocationSnapshot(
                memberAppleUserID: memberID,
                memberDisplayName: displayName,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracyMeters: location.horizontalAccuracy,
                altitudeMeters: location.altitude,
                speedMPS: location.speed,
                courseDegrees: location.course,
                recordedAt: location.timestamp,
                isSharingEnabled: true
            )
            row.circle = circle
            context.insert(row)
        }
    }

    private func markPausedRow(circleID: UUID) async {
        guard let author = currentAuthor() else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Circle>(predicate: #Predicate { $0.id == circleID })
        guard let circle = try? context.fetch(descriptor).first else { return }
        for row in circleLocations(circle: circle, context: context)
            where row.memberAppleUserID == author.appleUserID
        {
            row.isSharingEnabled = false
        }
        try? context.save()
    }

    private func circleLocations(circle: Circle, context: ModelContext) -> [LocationSnapshot] {
        let circleID = circle.id
        let descriptor = FetchDescriptor<LocationSnapshot>(
            predicate: #Predicate { $0.circle?.id == circleID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

extension LocationSharingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if !enabledCircleIDs.isEmpty, status == .authorizedWhenInUse || status == .authorizedAlways {
                startUpdates()
            }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let captured = location
        Task { @MainActor in
            lastLocation = captured
            lastError = nil
            await upsertSnapshot(captured)
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        let captured = error.localizedDescription
        Task { @MainActor in
            lastError = captured
            AppLogger.app.notice(
                "LocationSharingService error: \(captured, privacy: .public)"
            )
        }
    }
}
