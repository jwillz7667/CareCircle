import Foundation

// MARK: - CareRecipientDraft

struct CareRecipientDraft: Equatable, Sendable {
    var firstName = ""
    var lastName = ""
    var dateOfBirth: Date?
    var photoData: Data?
    var primaryConditionsInput = ""

    var primaryConditions: [String] {
        primaryConditionsInput
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLastName: String? {
        let trimmed = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var validationError: CareRecipientValidationError? {
        if trimmedFirstName.isEmpty {
            return .firstNameRequired
        }
        if trimmedFirstName.count > 60 {
            return .firstNameTooLong
        }
        if let dob = dateOfBirth, dob > .now {
            return .dobInFuture
        }
        return nil
    }

    var isValid: Bool {
        validationError == nil
    }

    /// Returns a draft populated from an existing Care Recipient (for edit mode).
    static func from(_ recipient: CareRecipient) -> Self {
        Self(
            firstName: recipient.firstName,
            lastName: recipient.lastName ?? "",
            dateOfBirth: recipient.dateOfBirth,
            photoData: recipient.photoData,
            primaryConditionsInput: recipient.primaryConditions.joined(separator: ", ")
        )
    }

    /// Writes the draft into an existing Care Recipient (edit save path).
    func apply(to recipient: CareRecipient) {
        recipient.firstName = trimmedFirstName
        recipient.lastName = trimmedLastName
        recipient.dateOfBirth = dateOfBirth
        recipient.photoData = photoData
        recipient.primaryConditions = primaryConditions
    }

    /// Constructs a new Care Recipient from the draft (create save path).
    func makeCareRecipient() -> CareRecipient {
        CareRecipient(
            firstName: trimmedFirstName,
            lastName: trimmedLastName,
            dateOfBirth: dateOfBirth,
            photoData: photoData,
            primaryConditions: primaryConditions
        )
    }
}

// MARK: - CareRecipientValidationError

enum CareRecipientValidationError: LocalizedError, Sendable, Equatable {
    case firstNameRequired
    case firstNameTooLong
    case dobInFuture

    var errorDescription: String? {
        switch self {
        case .firstNameRequired:
            "First name is required."
        case .firstNameTooLong:
            "First name must be 60 characters or fewer."
        case .dobInFuture:
            "Date of birth cannot be in the future."
        }
    }
}
