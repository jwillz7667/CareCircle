import Foundation
import SwiftData

// MARK: - EmergencyContact

/// Lightweight phonebook for an SOS event to dial. v1 keeps name +
/// phone in plaintext: per the database spec §4.18 a name + number
/// pair plus a relationship label is not considered PHI when isolated
/// from a Care Recipient's health details. Future tightening can move
/// `phoneE164` behind `DocumentVault`.
@Model
final class EmergencyContact {
    var id = UUID()
    var name = ""
    var relationship: String?
    var phoneE164 = ""
    var isPrimary = false
    var isMedical = false
    var sortOrder = 100
    var createdAt = Date.now
    var updatedAt = Date.now

    var circle: Circle?

    init(
        id: UUID = UUID(),
        name: String,
        relationship: String? = nil,
        phoneE164: String,
        isPrimary: Bool = false,
        isMedical: Bool = false,
        sortOrder: Int = 100,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.relationship = relationship
        self.phoneE164 = phoneE164
        self.isPrimary = isPrimary
        self.isMedical = isMedical
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        updatedAt = createdAt
    }
}
