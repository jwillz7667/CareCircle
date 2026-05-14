import Foundation

// MARK: - BackendRealtimeFrame

/// Decoded wire frame from `GET /v1/realtime`. The backend emits two
/// shapes — a single `subscribed` envelope on connect listing the
/// circles this socket can hear about, and one `change` envelope per
/// row mutation. The payload is intentionally lean: no row contents,
/// just an `(table, rowId)` pair the client uses to refetch via the
/// RLS-protected REST endpoints.
nonisolated enum BackendRealtimeFrame: Sendable, Equatable {
    case subscribed(circles: [UUID])
    case change(circleId: UUID, table: String, rowId: UUID, op: String)

    static func decode(from data: Data) -> BackendRealtimeFrame? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return nil
        }
        switch envelope.type {
        case "subscribed":
            let circles = (envelope.circles ?? []).compactMap(UUID.init(uuidString:))
            return .subscribed(circles: circles)
        case "change":
            guard let circleRaw = envelope.circleId,
                  let circleId = UUID(uuidString: circleRaw),
                  let table = envelope.table,
                  let rowRaw = envelope.rowId,
                  let rowId = UUID(uuidString: rowRaw),
                  let op = envelope.op else { return nil }
            return .change(circleId: circleId, table: table, rowId: rowId, op: op)
        default:
            return nil
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let circles: [String]?
        let circleId: String?
        let table: String?
        let rowId: String?
        let op: String?
    }
}
