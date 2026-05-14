import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - BackendRealtimeClient

/// Maintains a persistent WebSocket to the Railway backend's
/// `/v1/realtime` endpoint so member devices learn about row-level
/// mutations from other Circle members as they happen, rather than
/// waiting for the next cold-start hydration pass.
///
/// **Frame wire shape.** The server emits:
///
/// ```
/// { "type": "subscribed", "circles": ["<uuid>", …] }
/// { "type": "change",
///   "circleId": "<uuid>", "table": "<name>",
///   "rowId": "<uuid>", "op": "INSERT"|"UPDATE"|"DELETE" }
/// ```
///
/// Dispatches each `change` to a per-domain applicator that refetches
/// the list (or the single row, for doses) and upserts into SwiftData.
/// Phase 23 added UPDATE + soft-delete handling: non-paginated domains
/// (medications/appointments/members/contacts/documents) treat "absent
/// from response" as a soft-delete signal; paginated domains
/// (activities/sos/care-minutes) upsert only and defer delete
/// propagation to cold-start hydration.
///
/// **Lifecycle.** `RootView` calls `start(modelContext:)` after
/// hydration and on scene-phase `.active`; `stop()` is called on
/// `.background`/`.inactive` so a phone in a pocket doesn't keep a
/// socket open. Auth failures (4401) bail without retry; transport
/// failures retry with exponential backoff (5s → 15s → 30s → 60s cap)
/// reset on the next successful frame.
@Observable
@MainActor
final class BackendRealtimeClient {
    private(set) var isConnected = false
    private(set) var lastConnectedAt: Date?
    private(set) var lastChangeAt: Date?
    private(set) var subscribedCircleCount = 0
    private(set) var lastError: String?

    // Resync state lives outside `private(set)` because the
    // `BackendRealtimeSnapshot` extension lives in another file and
    // needs to mutate them. Module-internal write access is fine —
    // no external code should be reaching in.
    var lastResyncAt: Date?
    var isResyncing = false

    /// Tracks whether this client instance has been subscribed at least
    /// once. The first subscribed frame is *not* a reconnect — cold-start
    /// hydration owns the initial fetch. Every subsequent subscribed
    /// frame is a reconnect and triggers a snapshot resync.
    var hasPriorConnection = false

    let apiClient: APIClient
    private let configuration: BackendConfiguration
    private let urlSession: URLSession
    private let currentBackendUserID: @MainActor () -> String?
    private var connectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var webSocket: URLSessionWebSocketTask?
    private var reconnectAttempt = 0
    private var stoppedByUser = false

    init(
        apiClient: APIClient,
        configuration: BackendConfiguration,
        urlSession: URLSession = .shared,
        currentBackendUserID: @escaping @MainActor () -> String? = { nil }
    ) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.urlSession = urlSession
        self.currentBackendUserID = currentBackendUserID
    }

    /// Connects if not already connected. Idempotent: a second call
    /// while the socket is up is a no-op. `modelContext` is captured so
    /// the receive loop can apply incoming changes; callers should
    /// supply the same context they use elsewhere in the view tree.
    func start(modelContext: ModelContext) {
        stoppedByUser = false
        guard connectTask == nil, webSocket == nil else { return }

        connectTask = Task { [weak self] in
            await self?.connect(modelContext: modelContext)
            await MainActor.run {
                self?.connectTask = nil
            }
        }
    }

    /// Cancels the active socket and any pending reconnect. Safe to
    /// call repeatedly. Sets `stoppedByUser` so an in-flight
    /// `connect()` won't auto-reconnect after teardown.
    func stop() {
        stoppedByUser = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        connectTask?.cancel()
        connectTask = nil
        isConnected = false
        subscribedCircleCount = 0
    }

    private func connect(modelContext: ModelContext) async {
        let token: String
        do {
            token = try await apiClient.freshAccessToken()
        } catch {
            lastError = "Auth: \(error.errorDescription ?? "no token")"
            AppLogger.backend.error(
                "Realtime token fetch failed: \(String(describing: error), privacy: .public)"
            )
            // Without a token, no point retrying — wait for the next
            // foreground tick (which will call start again).
            return
        }

        guard let url = buildRealtimeURL(token: token) else {
            lastError = "Realtime URL malformed"
            AppLogger.backend.error("Realtime URL could not be built.")
            return
        }

        let task = urlSession.webSocketTask(with: url)
        webSocket = task
        task.resume()
        AppLogger.backend.info("Realtime: connecting…")

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task, modelContext: modelContext)
        }
    }

    private func receiveLoop(
        task: URLSessionWebSocketTask,
        modelContext: ModelContext
    ) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                await handleMessage(message, modelContext: modelContext)
            } catch {
                handleReceiveFailure(error: error, modelContext: modelContext)
                return
            }
        }
    }

    private func handleMessage(
        _ message: URLSessionWebSocketTask.Message,
        modelContext: ModelContext
    ) async {
        let data: Data
        switch message {
        case let .data(payload):
            data = payload
        case let .string(text):
            data = Data(text.utf8)
        @unknown default:
            return
        }
        guard let frame = BackendRealtimeFrame.decode(from: data) else {
            AppLogger.backend.notice("Realtime: dropped undecodable frame")
            return
        }
        switch frame {
        case let .subscribed(circles):
            handleSubscribed(circles: circles, modelContext: modelContext)
        case let .change(circleId, table, rowId, op):
            lastChangeAt = .now
            isConnected = true
            reconnectAttempt = 0
            await dispatchChange(
                circleId: circleId,
                table: table,
                rowId: rowId,
                op: op,
                modelContext: modelContext
            )
        }
    }

    private func handleSubscribed(circles: [UUID], modelContext: ModelContext) {
        let wasReconnect = hasPriorConnection
        hasPriorConnection = true
        subscribedCircleCount = circles.count
        isConnected = true
        lastConnectedAt = .now
        lastError = nil
        reconnectAttempt = 0
        AppLogger.backend.info(
            "Realtime: subscribed to \(circles.count, privacy: .public) circle(s)."
        )
        guard wasReconnect, !circles.isEmpty else { return }
        let circlesToResync = circles
        Task { [weak self] in
            await self?.snapshotResync(
                circleIds: circlesToResync,
                modelContext: modelContext
            )
        }
    }

    private func handleReceiveFailure(
        error: Error,
        modelContext: ModelContext
    ) {
        let nsError = error as NSError
        let closeCode = webSocket?.closeCode ?? .invalid
        isConnected = false
        subscribedCircleCount = 0
        webSocket = nil
        receiveTask = nil

        if closeCode.rawValue == 4_401 {
            lastError = "Realtime auth failed (4401)"
            AppLogger.backend.error("Realtime: auth rejected by server.")
            return
        }

        lastError = nsError.localizedDescription
        AppLogger.backend.notice(
            "Realtime: receive ended (\(nsError.code, privacy: .public)) — \(nsError.localizedDescription, privacy: .public)"
        )

        guard !stoppedByUser else { return }
        scheduleReconnect(modelContext: modelContext)
    }

    private func scheduleReconnect(modelContext: ModelContext) {
        reconnectTask?.cancel()
        let delay = backoffDelay(forAttempt: reconnectAttempt)
        reconnectAttempt = min(reconnectAttempt + 1, 8)
        let attemptLogValue = reconnectAttempt
        AppLogger.backend.info(
            "Realtime: reconnecting in \(delay, privacy: .public)s (attempt \(attemptLogValue, privacy: .public))"
        )
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.reconnectTask = nil
            }
            start(modelContext: modelContext)
        }
    }

    private func backoffDelay(forAttempt attempt: Int) -> Double {
        // 5, 15, 30, 60, 60, 60, …
        switch attempt {
        case 0: 5
        case 1: 15
        case 2: 30
        default: 60
        }
    }

    private func buildRealtimeURL(token: String) -> URL? {
        guard var components = URLComponents(
            url: configuration.baseURL,
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.scheme = (components.scheme == "https") ? "wss" : "ws"
        components.path = "/v1/realtime"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    // MARK: - Dispatch

    private func dispatchChange(
        circleId: UUID,
        table: String,
        rowId: UUID,
        op _: String,
        modelContext: ModelContext
    ) async {
        switch table {
        case "activities":
            await applyActivityChange(circleId: circleId, modelContext: modelContext)
        case "medications":
            await applyMedicationChange(circleId: circleId, modelContext: modelContext)
        case "appointments":
            await applyAppointmentChange(circleId: circleId, modelContext: modelContext)
        case "circle_members":
            await applyMemberChange(circleId: circleId, modelContext: modelContext)
        case "emergency_contacts":
            await applyEmergencyContactChange(circleId: circleId, modelContext: modelContext)
        case "documents":
            await applyDocumentChange(circleId: circleId, modelContext: modelContext)
        case "sos_events":
            await applySosChange(circleId: circleId, modelContext: modelContext)
        case "dose_events":
            await applyDoseChange(rowId: rowId, modelContext: modelContext)
        case "care_minute_entries":
            await applyCareMinuteChange(circleId: circleId, modelContext: modelContext)
        default:
            AppLogger.backend.debug(
                "Realtime: \(table, privacy: .public) row \(rowId.uuidString, privacy: .public) — no applicator yet."
            )
        }
    }

    func fetchCircle(id: UUID, modelContext: ModelContext) -> Circle? {
        let descriptor = FetchDescriptor<Circle>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    func currentBackendUserId() -> String? {
        currentBackendUserID()
    }
}
