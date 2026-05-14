import Foundation
import SwiftData

// MARK: - Insight

/// A system-derived observation about a Circle's care patterns. Insights
/// are fully reconstructible from the underlying data (doses, vitals,
/// journal entries); we persist them only to remember dismissals and
/// to drive the unread-count badge.
///
/// **Per-device by design.** An insight dismissed on one caregiver's
/// phone stays visible on another caregiver's phone — different members
/// of the Circle may find different observations relevant. Insights are
/// not synced through CloudKit or the Railway backend.
@Model
final class Insight {
    var id = UUID()
    var kindRaw: String = InsightKind.doseTimingDrift.rawValue
    var severityRaw: String = InsightSeverity.info.rawValue
    var subjectKindRaw: String = InsightSubjectKind.circle.rawValue
    var subjectId: UUID?
    var title = ""
    var body = ""
    var computedAt = Date.now
    var dismissedAt: Date?
    var appliedAt: Date?
    /// `dedupeKey = "<kind>:<subjectKind>:<subjectId|none>"`. Stored on
    /// the row (rather than recomputed every fetch) so `#Predicate`
    /// lookups during recompute are O(log n) on an indexed column.
    var dedupeKey = ""
    /// Optional payload that an apply CTA may need (e.g., suggested
    /// reminder time in minutes from midnight). JSON-encoded so the
    /// schema doesn't grow per pattern.
    var payloadJSON: String?

    var circle: Circle?

    var kind: InsightKind {
        get { InsightKind(rawValue: kindRaw) ?? .doseTimingDrift }
        set { kindRaw = newValue.rawValue }
    }

    var severity: InsightSeverity {
        get { InsightSeverity(rawValue: severityRaw) ?? .info }
        set { severityRaw = newValue.rawValue }
    }

    var subjectKind: InsightSubjectKind {
        get { InsightSubjectKind(rawValue: subjectKindRaw) ?? .circle }
        set { subjectKindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: InsightKind,
        severity: InsightSeverity,
        subjectKind: InsightSubjectKind,
        subjectId: UUID?,
        title: String,
        body: String,
        computedAt: Date = .now,
        dismissedAt: Date? = nil,
        appliedAt: Date? = nil,
        dedupeKey: String,
        payloadJSON: String? = nil
    ) {
        self.id = id
        kindRaw = kind.rawValue
        severityRaw = severity.rawValue
        subjectKindRaw = subjectKind.rawValue
        self.subjectId = subjectId
        self.title = title
        self.body = body
        self.computedAt = computedAt
        self.dismissedAt = dismissedAt
        self.appliedAt = appliedAt
        self.dedupeKey = dedupeKey
        self.payloadJSON = payloadJSON
    }

    static func dedupeKey(
        kind: InsightKind,
        subjectKind: InsightSubjectKind,
        subjectId: UUID?
    )
        -> String
    {
        "\(kind.rawValue):\(subjectKind.rawValue):\(subjectId?.uuidString.lowercased() ?? "none")"
    }
}
