import Foundation
import SwiftData

// MARK: - CareRecipient

@Model
final class CareRecipient {
    @Attribute(.unique) var id: UUID
    var firstName: String
    var lastName: String?
    var dateOfBirth: Date?

    @Attribute(.externalStorage)
    var photoData: Data?

    var primaryConditions: [String]
    var createdAt: Date

    var circle: Circle?

    init(
        id: UUID = UUID(),
        firstName: String,
        lastName: String? = nil,
        dateOfBirth: Date? = nil,
        photoData: Data? = nil,
        primaryConditions: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.photoData = photoData
        self.primaryConditions = primaryConditions
        self.createdAt = createdAt
    }

    var fullName: String {
        let trimmedLast = lastName?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmedLast.isEmpty {
            return firstName
        }
        return "\(firstName) \(trimmedLast)"
    }

    var ageYears: Int? {
        guard let dob = dateOfBirth else { return nil }
        let components = Calendar.current.dateComponents([.year], from: dob, to: .now)
        return components.year
    }
}
