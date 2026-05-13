import CoreLocation
import Foundation
import OSLog

// MARK: - SOSLocation

/// A captured GPS fix with horizontal accuracy in meters. Optional in the
/// SOS pipeline: the user may not have granted location, or the fix may
/// time out during the 30-second countdown.
struct SOSLocation: Sendable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
}

// MARK: - SOSLocationProvider

/// Single-shot CoreLocation wrapper for SOS. We don't need continuous
/// updates — the SOS countdown asks for one fix at fire time. Authorization
/// is requested on first use; if denied, `requestFix` resolves to `nil` so
/// the rest of the SOS pipeline can keep moving (the event still ships,
/// just without coordinates).
///
/// Concurrency note: `CLLocationManager` is `@MainActor`-bound by SDK
/// defaults in iOS 26 with strict concurrency, so this provider stays on
/// the main actor. The 5-second timeout is intentional — at T=0 we don't
/// want SOS to stall waiting for a GPS lock indoors.
final class SOSLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<SOSLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Returns a single best-effort fix. Resolves to `nil` if authorization
    /// is denied, the request times out, or CoreLocation reports an error.
    /// Safe to call repeatedly; concurrent calls collapse onto the same
    /// pending fix.
    func requestFix(timeout: Duration = .seconds(5)) async -> SOSLocation? {
        if continuation != nil {
            AppLogger.sos.warning("requestFix called while another fix is pending; ignoring")
            return nil
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            AppLogger.sos.notice("Location authorization denied; proceeding without coordinates")
            return nil
        default:
            break
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            scheduleTimeout(timeout)
        }
    }

    private func scheduleTimeout(_ timeout: Duration) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled else { return }
            resolve(with: nil, reason: "timeout")
        }
    }

    private func resolve(with location: SOSLocation?, reason: String) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        AppLogger.sos.debug("SOS fix resolved (\(reason, privacy: .public))")
        continuation.resume(returning: location)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let fix = locations.last else { return }
        let captured = SOSLocation(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            accuracyMeters: fix.horizontalAccuracy
        )
        Task { @MainActor [weak self] in
            self?.resolve(with: captured, reason: "fix")
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didFailWithError error: Error
    ) {
        let described = String(describing: error)
        Task { @MainActor [weak self] in
            AppLogger.sos.error("CoreLocation error: \(described, privacy: .public)")
            self?.resolve(with: nil, reason: "error")
        }
    }
}
