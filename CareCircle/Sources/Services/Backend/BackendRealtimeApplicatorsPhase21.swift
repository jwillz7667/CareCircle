import Foundation
import OSLog
import SwiftData

// MARK: - Phase 20 / 21 applicators

/// Per-domain realtime applicators for the six list-shaped tables wired
/// in Phase 20 (activities) and Phase 21 (medications, appointments,
/// circle_members, emergency_contacts, documents). Phase 23 promoted
/// every applicator from insert-only to a full upsert + soft-delete
/// merge driven by `UpsertSpec`.
///
/// Lives in its own file (alongside `BackendRealtimeApplicatorsPhase22`)
/// so `BackendRealtimeClient.swift` stays under the swiftlint length
/// thresholds.
///
/// **Pagination caveat.** `activities` is cursor-paginated (20 rows),
/// so "absent from response" cannot distinguish a soft-delete from a
/// row that simply rolled off the page. The activity applicator
/// therefore sets `deleteAbsent: false`; cold-start hydration is
/// authoritative for activity deletes. The other five domains return
/// the full `deleted_at IS NULL` slice, so `deleteAbsent: true` is
/// safe and is how soft-deletes propagate via realtime.
extension BackendRealtimeClient {
    func applyActivityChange(
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
            logRefetchFailure(domain: "activities", error: error)
            return
        }
        upsertList(
            response.activities,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "activities",
                deleteAbsent: false,
                localPredicate: #Predicate<Activity> { $0.circle?.id == circleId },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeActivity(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateActivity(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
    }

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
        upsertList(
            response.medications,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "medications",
                deleteAbsent: true,
                localPredicate: #Predicate<Medication> { $0.circle?.id == circleId },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeMedication(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateMedication(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
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
        upsertList(
            response.appointments,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "appointments",
                deleteAbsent: true,
                localPredicate: #Predicate<Appointment> { $0.circle?.id == circleId },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeAppointment(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateAppointment(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
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
        upsertList(
            response.members,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "members",
                deleteAbsent: true,
                localPredicate: #Predicate<Member> { $0.circle?.id == circleId },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeMember(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateMember(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
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
        upsertList(
            response.contacts,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "emergency-contacts",
                deleteAbsent: true,
                localPredicate: #Predicate<EmergencyContact> { $0.circle?.id == circleId },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeEmergencyContact(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateEmergencyContact(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
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
        upsertList(
            response.documents,
            spec: UpsertSpec(
                circle: circle,
                circleId: circleId,
                domain: "documents",
                deleteAbsent: true,
                localPredicate: #Predicate<Document> { $0.circle?.id == circleId },
                parseID: { BackendHydratorMappers.parseUUID($0.id) },
                insert: { dto, parent in
                    let row = BackendHydratorMappers.makeDocumentPlaceholder(from: dto)
                    row.circle = parent
                    return row
                },
                update: { row, dto in
                    BackendHydratorMappers.updateDocument(row, from: dto)
                }
            ),
            modelContext: modelContext
        )
    }

    func logRefetchFailure(domain: String, error: Error) {
        AppLogger.backend.error(
            "Realtime: \(domain, privacy: .public) refetch failed: \(String(describing: error), privacy: .public)"
        )
    }
}
