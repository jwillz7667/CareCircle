import Foundation
import SwiftData

// MARK: - Vital

/// A point-in-time vital sign reading recorded for the Care Recipient.
/// Source is either a caregiver's manual entry or a sample imported
/// from HealthKit. Blood pressure is stored as two separate rows
/// (systolic + diastolic) sharing the same `recordedAt` so the UI can
/// pair them on display while the schema stays uniform.
///
/// The optional free-text `notes` field is plaintext locally (SwiftData
/// + CloudKit private DB), and envelope-encrypted on the backend per
/// the per-circle DEK. Numeric value, unit, and recordedAt stay
/// plaintext so list rendering / sort / future trend computation can
/// happen without decryption.
@Model
final class Vital {
    var id = UUID()
    var kindRaw: String = VitalKind.heartRate.rawValue
    var recordedAt = Date.now
    /// Stored as Double for convenient SwiftData encoding; UI formats
    /// per `unit`. Blood-pressure rows use mmHg (Int values); weight
    /// uses lb or kg; glucose uses mg/dL or mmol/L; SpO2 uses % (0-100).
    var valueNumeric: Double?
    /// Used when the reading is not a single scalar (e.g. blood-pressure
    /// "120/80" entered as a single composite by a user who hasn't seen
    /// the two-row form). The two-row form is preferred — `valueText` is
    /// a legacy / sketch field, kept for backend parity.
    var valueText: String?
    var unit = ""
    var sourceRaw: String = VitalSource.manual.rawValue
    /// HealthKit sample UUID — used to enforce one-row-per-sample-per-
    /// circle on imports. Stable for the lifetime of the HK sample.
    var healthkitUUID: String?
    var notes: String?
    var recordedByAppleUserID = ""
    var recordedByDisplayName = ""
    var createdAt = Date.now

    var circle: Circle?

    var kind: VitalKind {
        get { VitalKind(rawValue: kindRaw) ?? .heartRate }
        set { kindRaw = newValue.rawValue }
    }

    var source: VitalSource {
        get { VitalSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: VitalKind,
        recordedAt: Date,
        valueNumeric: Double? = nil,
        valueText: String? = nil,
        unit: String,
        source: VitalSource = .manual,
        healthkitUUID: String? = nil,
        notes: String? = nil,
        recordedByAppleUserID: String,
        recordedByDisplayName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        kindRaw = kind.rawValue
        self.recordedAt = recordedAt
        self.valueNumeric = valueNumeric
        self.valueText = valueText
        self.unit = unit
        sourceRaw = source.rawValue
        self.healthkitUUID = healthkitUUID
        self.notes = notes
        self.recordedByAppleUserID = recordedByAppleUserID
        self.recordedByDisplayName = recordedByDisplayName
        self.createdAt = createdAt
    }
}
