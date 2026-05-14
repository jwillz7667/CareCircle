import Foundation
import Observation
import OSLog
import SwiftData
import UIKit
import UserNotifications

// MARK: - SOSCenterError

enum SOSCenterError: LocalizedError {
    case alreadyArmed
    case noCircle
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyArmed:
            "SOS is already running."
        case .noCircle:
            "Create your Circle before you can trigger an SOS."
        case let .persistenceFailed(message):
            message
        }
    }
}

// MARK: - SOSCenterState

enum SOSCenterState: Equatable {
    case idle
    case arming(secondsRemaining: Int)
    case fired(eventID: UUID)
    case canceled
}

// MARK: - SOSCenter

/// Drives the SOS lifecycle: arm → 30-second countdown with escalating
/// haptics → fire (persist SOSEvent, post local alert, capture location)
/// → optionally cancel mid-countdown. Single instance per app, injected
/// via `@Environment(SOSCenter.self)` so views can observe state changes.
///
/// CloudKit propagation: writing the SOSEvent into the circle's shared
/// SwiftData store causes the normal CKShare sync to push it to other
/// members' devices. No custom fan-out — the cost of remote-device alerting
/// without the app running is the Critical Alert entitlement, which Apple
/// grants case by case. Until then, member devices learn about an SOS the
/// next time their app foregrounds or pulls a sync event.
@MainActor
@Observable
final class SOSCenter {
    private(set) var state: SOSCenterState = .idle

    private let locationProvider: SOSLocationProvider
    private let armDuration: Int
    private var countdownTask: Task<Void, Never>?
    private var hapticGenerator: UIImpactFeedbackGenerator?

    init(
        locationProvider: SOSLocationProvider? = nil,
        armDuration: Int = 30
    ) {
        self.locationProvider = locationProvider ?? SOSLocationProvider()
        self.armDuration = armDuration
    }

    /// Starts the 30-second countdown. Caller passes the model context and
    /// the user / circle so the orchestrator can write the SOSEvent at T=0
    /// without reaching into SwiftUI environment values. `syncEngine` mirrors
    /// the fired event to the backend queue.
    func arm(
        in circle: Circle,
        triggeredBy user: SignedInUser,
        modelContext: ModelContext,
        syncEngine: SyncEngine
    ) async throws(SOSCenterError) {
        guard case .idle = state else { throw .alreadyArmed }
        await SOSNotificationAuthorizer.requestAuthorization()

        state = .arming(secondsRemaining: armDuration)
        countdownTask = Task { [weak self] in
            await self?.runCountdown(
                circle: circle,
                user: user,
                modelContext: modelContext,
                syncEngine: syncEngine
            )
        }
    }

    /// Cancels an in-flight countdown without persisting an SOSEvent. No-op
    /// when SOS has already fired (use `markCanceled` on the persisted event
    /// for that).
    func cancel() {
        guard case .arming = state else { return }
        countdownTask?.cancel()
        countdownTask = nil
        hapticGenerator = nil
        state = .canceled
        AppLogger.sos.info("SOS countdown canceled by user")
    }

    func reset() {
        countdownTask?.cancel()
        countdownTask = nil
        hapticGenerator = nil
        state = .idle
    }

    // MARK: Countdown

    private func runCountdown(
        circle: Circle,
        user: SignedInUser,
        modelContext: ModelContext,
        syncEngine: SyncEngine
    ) async {
        hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
        hapticGenerator?.prepare()

        for tick in stride(from: armDuration, through: 1, by: -1) {
            if Task.isCancelled { return }
            state = .arming(secondsRemaining: tick)
            triggerHaptic(secondsRemaining: tick)

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
        }

        if Task.isCancelled { return }
        await fire(circle: circle, user: user, modelContext: modelContext, syncEngine: syncEngine)
    }

    private func triggerHaptic(secondsRemaining: Int) {
        if secondsRemaining.isMultiple(of: 5) || secondsRemaining <= 5 {
            hapticGenerator?.impactOccurred()
        }
    }

    // MARK: Fire

    private func fire(
        circle: Circle,
        user: SignedInUser,
        modelContext: ModelContext,
        syncEngine: SyncEngine
    ) async {
        let location = await locationProvider.requestFix()
        let event = SOSEvent(
            triggeredByAppleUserID: user.id,
            triggeredByDisplayName: user.displayName,
            triggeredAt: .now,
            latitude: location?.latitude,
            longitude: location?.longitude,
            locationAccuracyMeters: location?.accuracyMeters
        )
        event.circle = circle

        modelContext.insert(event)
        do {
            try modelContext.save()
            syncEngine.enqueueSOSEventCreate(event)
        } catch {
            let described = String(describing: error)
            AppLogger.sos.error("Failed to persist SOSEvent: \(described, privacy: .public)")
        }

        await postLocalAlert(event: event, triggeredBy: user)
        state = .fired(eventID: event.id)
        AppLogger.sos.info("SOS fired event=\(event.id.uuidString, privacy: .public)")
    }

    private func postLocalAlert(event: SOSEvent, triggeredBy user: SignedInUser) async {
        let content = UNMutableNotificationContent()
        content.title = "SOS triggered"
        content.body = "\(user.displayName) requested help. Tap to view details."
        content.sound = .defaultCritical
        // TODO: when Critical Alert entitlement is granted, switch to .critical
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "SOS_EVENT"
        content.userInfo = ["sos_event_id": event.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "sos.event.\(event.id.uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            let described = String(describing: error)
            AppLogger.sos.error("Local SOS alert failed: \(described, privacy: .public)")
        }
    }
}
