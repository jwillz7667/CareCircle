import Foundation
import OSLog
import SwiftData
import UserNotifications

// MARK: - BackendHydrator

/// Cold-start hydrator: pulls each domain from the Railway backend and
/// inserts rows into SwiftData **only when the local store is empty for
/// that domain in this circle**. The empty-domain gate keeps Phase 16
/// off the toes of the CloudKit replication path — when the device
/// already has CloudKit-synced rows, hydration is a no-op for that
/// table. Full row-level merge is Phase 17.
///
/// One hydrator instance is shared for the app's lifetime so the UI can
/// surface `lastRunAt` and `lastError`. A single `hydrate(...)` call
/// invokes one fan-out across all supported domains; concurrent calls
/// are coalesced via `inFlight` so a debug-row "Pull now" tap during a
/// foreground hydration doesn't double-run.
@Observable
@MainActor
final class BackendHydrator {
    private(set) var lastRunAt: Date?
    private(set) var lastError: String?
    private(set) var isRunning = false

    // Internal so the SOS reconcile extension in
    // `BackendHydratorSOSReconcile.swift` can issue its own GET. Same
    // visibility pattern as `BackendRealtimeClient.apiClient`.
    let apiClient: APIClient
    private var inFlight: Task<Void, Never>?

    /// Bound on activity pagination so launch latency stays predictable
    /// (5 × 50 ≈ 250 rows worst case). Older entries can be pulled on
    /// demand once Phase 17 introduces full inbound merge.
    private static let activityPageLimit = 50
    private static let activityMaxPages = 5
    private static let shiftDigestPageLimit = 50
    private static let shiftDigestMaxPages = 5

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// Kicks off a hydration pass for every circle in the local store.
    /// Safe to call from `RootView.onAppear`, a debug-row "Pull now"
    /// tap, or a foreground transition.
    func triggerHydrateAll(modelContext: ModelContext) {
        guard inFlight == nil else {
            AppLogger.backend.info("Hydrate skipped — already in flight.")
            return
        }
        let circleIDs = fetchAllCircleIDs(modelContext: modelContext)
        guard !circleIDs.isEmpty else {
            AppLogger.backend.info("Hydrate skipped — no local circles.")
            return
        }
        inFlight = Task { [weak self] in
            await self?.hydrateAll(circleIDs: circleIDs, modelContext: modelContext)
            await MainActor.run {
                self?.inFlight = nil
            }
        }
    }

    /// Runs a single hydration pass across one or more circles. Exposed
    /// for the debug row so the UI can `await` the result before
    /// re-rendering.
    func hydrateAll(circleIDs: [UUID], modelContext: ModelContext) async {
        isRunning = true
        defer { isRunning = false }

        var lastReportedError: String?
        for circleId in circleIDs {
            await hydrate(circleId: circleId, modelContext: modelContext)
            if let error = lastError {
                lastReportedError = error
            }
        }
        lastError = lastReportedError
        if lastReportedError == nil {
            lastRunAt = .now
        }
    }

    private func fetchAllCircleIDs(modelContext: ModelContext) -> [UUID] {
        let descriptor = FetchDescriptor<Circle>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContext.fetch(descriptor))?.map(\.id) ?? []
    }

    /// Runs hydration for a single circle. Internal — callers should
    /// prefer `triggerHydrateAll(...)` or `hydrateAll(circleIDs:...)`.
    private func hydrate(circleId: UUID, modelContext: ModelContext) async {
        do {
            try await hydrateActivities(circleId: circleId, modelContext: modelContext)
            try await hydrateMedications(circleId: circleId, modelContext: modelContext)
            try await hydrateDoseEvents(circleId: circleId, modelContext: modelContext)
            try await hydrateAppointments(circleId: circleId, modelContext: modelContext)
            try await hydrateEmergencyContacts(circleId: circleId, modelContext: modelContext)
            try await hydrateMembers(circleId: circleId, modelContext: modelContext)
            try await hydrateCareMinutes(circleId: circleId, modelContext: modelContext)
            let sosRetractIDs = try await reconcileSOSEvents(
                circleId: circleId,
                modelContext: modelContext
            )
            try await hydrateDocuments(circleId: circleId, modelContext: modelContext)
            try await hydrateShiftDigests(circleId: circleId, modelContext: modelContext)
            try await hydrateVitals(circleId: circleId, modelContext: modelContext)

            try modelContext.save()
            retractStaleSOSNotifications(identifiers: sosRetractIDs)
            lastError = nil
            AppLogger.backend.info(
                "Hydrate run complete for circle \(circleId.uuidString, privacy: .public)."
            )
        } catch let error as APIError {
            lastError = error.errorDescription ?? "API error"
            AppLogger.backend.error(
                "Hydrate failed: \(String(describing: error), privacy: .public)"
            )
        } catch {
            lastError = error.localizedDescription
            AppLogger.backend.error(
                "Hydrate failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Per-domain helpers

    private func hydrateActivities(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: Activity.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Activities skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        var cursor: String?
        var pageCount = 0
        var inserted = 0
        while pageCount < Self.activityMaxPages {
            let path = activityListPath(circleId: circleId, cursor: cursor)
            let response: ActivitiesResponse = try await apiClient.send(
                method: .get,
                path: path,
                authenticated: true
            )

            for dto in response.activities {
                let activity = BackendHydratorMappers.makeActivity(from: dto)
                activity.circle = circle
                modelContext.insert(activity)
                inserted += 1
            }

            cursor = response.nextCursor
            pageCount += 1
            if cursor == nil { break }
        }
        AppLogger.backend.info(
            "Hydrated \(inserted, privacy: .public) activities over \(pageCount, privacy: .public) pages."
        )
    }

    private func hydrateMedications(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: Medication.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Medications skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        let response: MedicationsResponse = try await apiClient.send(
            method: .get,
            path: "/v1/circles/\(circleId.uuidString.lowercased())/medications",
            authenticated: true
        )
        for dto in response.medications {
            let medication = BackendHydratorMappers.makeMedication(from: dto)
            medication.circle = circle
            modelContext.insert(medication)
        }
        AppLogger.backend.info(
            "Hydrated \(response.medications.count, privacy: .public) medications."
        )
    }

    private func hydrateDoseEvents(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: DoseEvent.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Dose events skipped — local store is not empty.")
            return
        }

        let medications = fetchMedications(circleId: circleId, modelContext: modelContext)
        guard !medications.isEmpty else {
            AppLogger.backend.debug("Dose events skipped — no local medications.")
            return
        }

        var totalInserted = 0
        for medication in medications {
            let response: MedicationDosesResponse = try await apiClient.send(
                method: .get,
                path: "/v1/medications/\(medication.id.uuidString.lowercased())/doses",
                authenticated: true
            )
            for dto in response.doses {
                let dose = BackendHydratorMappers.makeDoseEvent(from: dto)
                dose.medication = medication
                modelContext.insert(dose)
                totalInserted += 1
            }
        }
        AppLogger.backend.info(
            "Hydrated \(totalInserted, privacy: .public) dose events across \(medications.count, privacy: .public) medications."
        )
    }

    private func hydrateAppointments(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: Appointment.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Appointments skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        let response: AppointmentsResponse = try await apiClient.send(
            method: .get,
            path: "/v1/circles/\(circleId.uuidString.lowercased())/appointments",
            authenticated: true
        )
        for dto in response.appointments {
            let appointment = BackendHydratorMappers.makeAppointment(from: dto)
            appointment.circle = circle
            modelContext.insert(appointment)
        }
        AppLogger.backend.info(
            "Hydrated \(response.appointments.count, privacy: .public) appointments."
        )
    }

    private func hydrateEmergencyContacts(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: EmergencyContact.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Emergency contacts skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        let response: EmergencyContactsResponse = try await apiClient.send(
            method: .get,
            path: "/v1/circles/\(circleId.uuidString.lowercased())/emergency-contacts",
            authenticated: true
        )
        for dto in response.contacts {
            let contact = BackendHydratorMappers.makeEmergencyContact(from: dto)
            contact.circle = circle
            modelContext.insert(contact)
        }
        AppLogger.backend.info(
            "Hydrated \(response.contacts.count, privacy: .public) emergency contacts."
        )
    }

    private func hydrateMembers(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: Member.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Members skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        let response: MembersResponse = try await apiClient.send(
            method: .get,
            path: "/v1/circles/\(circleId.uuidString.lowercased())/members",
            authenticated: true
        )
        for dto in response.members {
            let member = BackendHydratorMappers.makeMember(from: dto)
            member.circle = circle
            modelContext.insert(member)
        }
        AppLogger.backend.info(
            "Hydrated \(response.members.count, privacy: .public) members."
        )
    }

    private func hydrateCareMinutes(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: CareMinuteEntry.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Care minutes skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        let response: CareMinutesResponse = try await apiClient.send(
            method: .get,
            path: "/v1/circles/\(circleId.uuidString.lowercased())/care-minutes",
            authenticated: true
        )
        for dto in response.entries {
            let entry = BackendHydratorMappers.makeCareMinuteEntry(from: dto)
            entry.circle = circle
            modelContext.insert(entry)
        }
        AppLogger.backend.info(
            "Hydrated \(response.entries.count, privacy: .public) care-minute entries."
        )
    }

    private func hydrateDocuments(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: Document.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Documents skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        let response: DocumentsResponse = try await apiClient.send(
            method: .get,
            path: "/v1/circles/\(circleId.uuidString.lowercased())/documents",
            authenticated: true
        )
        for dto in response.documents {
            let document = BackendHydratorMappers.makeDocumentPlaceholder(from: dto)
            document.circle = circle
            modelContext.insert(document)
        }
        AppLogger.backend.info(
            "Hydrated \(response.documents.count, privacy: .public) document placeholders."
        )
    }

    private func hydrateShiftDigests(circleId: UUID, modelContext: ModelContext) async throws {
        guard localCount(of: ShiftDigest.self, in: circleId, modelContext: modelContext) == 0 else {
            AppLogger.backend.debug("Shift digests skipped — local store is not empty.")
            return
        }
        guard let circle = fetchCircle(id: circleId, modelContext: modelContext) else { return }

        var cursor: String?
        var pageCount = 0
        var inserted = 0
        while pageCount < Self.shiftDigestMaxPages {
            let path = shiftDigestListPath(circleId: circleId, cursor: cursor)
            let response: ShiftDigestsResponse = try await apiClient.send(
                method: .get,
                path: path,
                authenticated: true
            )
            for dto in response.digests {
                let digest = BackendHydratorMappers.makeShiftDigest(from: dto)
                digest.circle = circle
                modelContext.insert(digest)
                inserted += 1
            }
            cursor = response.nextCursor
            pageCount += 1
            if cursor == nil { break }
        }
        AppLogger.backend.info(
            "Hydrated \(inserted, privacy: .public) shift digests over \(pageCount, privacy: .public) pages."
        )
    }

    // MARK: - Local count + circle lookup

    private func localCount<Model: PersistentModel>(
        of _: Model.Type,
        in circleId: UUID,
        modelContext: ModelContext
    )
        -> Int
    {
        // Predicate over a `Circle?` relationship is awkward for the SwiftData
        // macro; fetching the typed list and counting matching `circle?.id`
        // values is correct and equally fast for the small per-circle row
        // counts hydration cares about.
        let descriptor = FetchDescriptor<Model>()
        do {
            let rows = try modelContext.fetch(descriptor)
            return rows.reduce(0) { acc, row in
                acc + (Self.circleId(of: row) == circleId ? 1 : 0)
            }
        } catch {
            AppLogger.backend.error(
                "Local count fetch failed for \(String(describing: Model.self), privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return 1 // pessimistic: behave as if we have data so we don't double-insert
        }
    }

    private static func circleId(of row: any PersistentModel) -> UUID? {
        if let dose = row as? DoseEvent { return dose.medication?.circle?.id }
        return circleScopedRowID(of: row)
    }

    private static func circleScopedRowID(of row: any PersistentModel) -> UUID? {
        switch row {
        case let row as Activity: row.circle?.id
        case let row as Medication: row.circle?.id
        case let row as Appointment: row.circle?.id
        case let row as EmergencyContact: row.circle?.id
        case let row as Member: row.circle?.id
        case let row as CareMinuteEntry: row.circle?.id
        case let row as SOSEvent: row.circle?.id
        case let row as Document: row.circle?.id
        case let row as ShiftDigest: row.circle?.id
        case let row as Vital: row.circle?.id
        default: nil
        }
    }

    func fetchCircle(id: UUID, modelContext: ModelContext) -> Circle? {
        let descriptor = FetchDescriptor<Circle>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchMedications(circleId: UUID, modelContext: ModelContext) -> [Medication] {
        let descriptor = FetchDescriptor<Medication>(sortBy: [SortDescriptor(\.createdAt)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { $0.circle?.id == circleId }
    }

    // MARK: - URL helpers

    private func activityListPath(circleId: UUID, cursor: String?) -> String {
        let base = "/v1/circles/\(circleId.uuidString.lowercased())/activities"
        var components = URLComponents()
        components.path = base
        var items = [URLQueryItem(name: "limit", value: "\(Self.activityPageLimit)")]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = items
        // `URLComponents` percent-encodes both pieces; combine them by hand
        // because `APIClient` takes a single path string.
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(base)\(query)"
    }

    private func shiftDigestListPath(circleId: UUID, cursor: String?) -> String {
        let base = "/v1/circles/\(circleId.uuidString.lowercased())/digests"
        var components = URLComponents()
        components.path = base
        var items = [URLQueryItem(name: "limit", value: "\(Self.shiftDigestPageLimit)")]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = items
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "\(base)\(query)"
    }
}
