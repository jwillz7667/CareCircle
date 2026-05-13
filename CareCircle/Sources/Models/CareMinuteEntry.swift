import Foundation
import SwiftData

// MARK: - CareMinuteEntry

/// A single block of paid care time. Records `startedAt` / `endedAt` plus
/// the HCBS service code; the daily / weekly rollups are computed in
/// `CareMinuteService`. `caregiverAppleUserID` is denormalized so an
/// exported PDF still attributes the row correctly even if the caregiver
/// later leaves the Circle.
@Model
final class CareMinuteEntry {
    var id = UUID()
    var caregiverAppleUserID = ""
    var caregiverDisplayName = ""
    var serviceCodeRaw = HCBSServiceCode.personalCare.rawValue
    var serviceDescription = ""
    var startedAt = Date.now
    var endedAt = Date.now
    var notes: String?
    var milesDriven: Double?
    var fiscalIntermediary: String?
    var exportedAt: Date?
    var createdAt = Date.now
    var updatedAt = Date.now

    var circle: Circle?

    init(
        id: UUID = UUID(),
        caregiverAppleUserID: String,
        caregiverDisplayName: String,
        serviceCode: HCBSServiceCode,
        serviceDescription: String,
        startedAt: Date,
        endedAt: Date,
        notes: String? = nil,
        milesDriven: Double? = nil,
        fiscalIntermediary: String? = nil
    ) {
        self.id = id
        self.caregiverAppleUserID = caregiverAppleUserID
        self.caregiverDisplayName = caregiverDisplayName
        serviceCodeRaw = serviceCode.rawValue
        self.serviceDescription = serviceDescription
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.milesDriven = milesDriven
        self.fiscalIntermediary = fiscalIntermediary
        let now = Date.now
        createdAt = now
        updatedAt = now
    }

    var serviceCode: HCBSServiceCode {
        get { HCBSServiceCode.from(raw: serviceCodeRaw) }
        set { serviceCodeRaw = newValue.rawValue }
    }

    var durationMinutes: Int {
        let seconds = endedAt.timeIntervalSince(startedAt)
        return max(0, Int(seconds / 60))
    }

    var durationHours: Double {
        Double(durationMinutes) / 60.0
    }
}
