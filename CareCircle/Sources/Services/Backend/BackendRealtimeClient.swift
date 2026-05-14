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
/// Phase 20 dispatches activity-table changes through
/// `applyActivityChange`, which fetches the most-recent page and
/// idempotently inserts unknown rows. Other tables log + ignore until
/// Phase 21 wires applicators for them.
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
            subscribedCircleCount = circles.count
            isConnected = true
            lastConnectedAt = .now
            lastError = nil
            reconnectAttempt = 0
            AppLogger.backend.info(
                "Realtime: subscribed to \(circles.count, privacy: .public) circle(s)."
            )
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

    private func applyActivityChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else {
            AppLogger.backend.debug(
                "Realtime: activity change for unknown circle \(circleId.uuidString, privacy: .public)"
            )
            return
        }

        let response: ActivitiesResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/activities?limit=20",
                authenticated: true
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: activity refetch failed: \(String(describing: error), privacy: .public)"
            )
            return
        }

        let existingIDs = fetchExistingActivityIDs(
            circleId: circleId,
            modelContext: modelContext
        )

        var inserted = 0
        for dto in response.activities {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id) else { continue }
            if existingIDs.contains(dtoID) { continue }
            let activity = BackendHydratorMappers.makeActivity(from: dto)
            activity.circle = circle
            modelContext.insert(activity)
            inserted += 1
        }

        guard inserted > 0 else { return }

        do {
            try modelContext.save()
            AppLogger.backend.info(
                "Realtime: inserted \(inserted, privacy: .public) activities for circle \(circleId.uuidString, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: save failed after activity merge: \(String(describing: error), privacy: .public)"
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

    private func fetchExistingActivityIDs(
        circleId: UUID,
        modelContext: ModelContext
    )
        -> Set<UUID>
    {
        let descriptor = FetchDescriptor<Activity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return Set(all.compactMap { $0.circle?.id == circleId ? $0.id : nil })
    }
}

// MARK: - Per-domain applicators

extension BackendRealtimeClient {
    func applyMedicationChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }
        let response: MedicationsResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/medications",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "medications", error: error)
            return
        }
        let existing = fetchExistingIDs(Medication.self, circleId: circleId, modelContext: modelContext) {
            $0.circle?.id
        }
        var inserted = 0
        for dto in response.medications {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id), !existing.contains(dtoID) else { continue }
            let row = BackendHydratorMappers.makeMedication(from: dto)
            row.circle = circle
            modelContext.insert(row)
            inserted += 1
        }
        saveIfInserted(inserted, domain: "medications", circleId: circleId, modelContext: modelContext)
    }

    func applyAppointmentChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }
        let response: AppointmentsResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/appointments",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "appointments", error: error)
            return
        }
        let existing = fetchExistingIDs(Appointment.self, circleId: circleId, modelContext: modelContext) {
            $0.circle?.id
        }
        var inserted = 0
        for dto in response.appointments {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id), !existing.contains(dtoID) else { continue }
            let row = BackendHydratorMappers.makeAppointment(from: dto)
            row.circle = circle
            modelContext.insert(row)
            inserted += 1
        }
        saveIfInserted(inserted, domain: "appointments", circleId: circleId, modelContext: modelContext)
    }

    func applyMemberChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }
        let response: MembersResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/members",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "members", error: error)
            return
        }
        let existing = fetchExistingIDs(Member.self, circleId: circleId, modelContext: modelContext) { $0.circle?.id }
        var inserted = 0
        for dto in response.members {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id), !existing.contains(dtoID) else { continue }
            let row = BackendHydratorMappers.makeMember(from: dto)
            row.circle = circle
            modelContext.insert(row)
            inserted += 1
        }
        saveIfInserted(inserted, domain: "members", circleId: circleId, modelContext: modelContext)
    }

    func applyEmergencyContactChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }
        let response: EmergencyContactsResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/emergency-contacts",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "emergency-contacts", error: error)
            return
        }
        let existing = fetchExistingIDs(EmergencyContact.self, circleId: circleId, modelContext: modelContext) {
            $0.circle?.id
        }
        var inserted = 0
        for dto in response.contacts {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id), !existing.contains(dtoID) else { continue }
            let row = BackendHydratorMappers.makeEmergencyContact(from: dto)
            row.circle = circle
            modelContext.insert(row)
            inserted += 1
        }
        saveIfInserted(inserted, domain: "emergency-contacts", circleId: circleId, modelContext: modelContext)
    }

    func applyDocumentChange(
        circleId: UUID,
        modelContext: ModelContext
    ) async {
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }
        let response: DocumentsResponse
        do {
            response = try await apiClient.send(
                method: .get,
                path: "/v1/circles/\(circleId.uuidString.lowercased())/documents",
                authenticated: true
            )
        } catch {
            logRefetchFailure(domain: "documents", error: error)
            return
        }
        let existing = fetchExistingIDs(Document.self, circleId: circleId, modelContext: modelContext) { $0.circle?.id }
        var inserted = 0
        for dto in response.documents {
            guard let dtoID = BackendHydratorMappers.parseUUID(dto.id), !existing.contains(dtoID) else { continue }
            let row = BackendHydratorMappers.makeDocumentPlaceholder(from: dto)
            row.circle = circle
            modelContext.insert(row)
            inserted += 1
        }
        saveIfInserted(inserted, domain: "documents", circleId: circleId, modelContext: modelContext)
    }

    func fetchExistingIDs<M: PersistentModel & Identifiable>(
        _: M.Type,
        circleId: UUID,
        modelContext: ModelContext,
        circleIDOf: (M) -> UUID?
    )
        -> Set<UUID> where M.ID == UUID
    {
        let all = (try? modelContext.fetch(FetchDescriptor<M>())) ?? []
        return Set(all.compactMap { circleIDOf($0) == circleId ? $0.id : nil })
    }

    func saveIfInserted(
        _ inserted: Int,
        domain: String,
        circleId: UUID,
        modelContext: ModelContext
    ) {
        guard inserted > 0 else { return }
        do {
            try modelContext.save()
            AppLogger.backend.info(
                "Realtime: inserted \(inserted, privacy: .public) \(domain, privacy: .public) for circle \(circleId.uuidString, privacy: .public)"
            )
        } catch {
            AppLogger.backend.error(
                "Realtime: save failed after \(domain, privacy: .public) merge: \(String(describing: error), privacy: .public)"
            )
        }
    }

    func logRefetchFailure(domain: String, error: Error) {
        AppLogger.backend.error(
            "Realtime: \(domain, privacy: .public) refetch failed: \(String(describing: error), privacy: .public)"
        )
    }
}
