import Foundation

// MARK: - SignedInUser

struct SignedInUser: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let givenName: String?
    let familyName: String?
    let email: String?

    var displayName: String {
        let parts = [givenName, familyName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: " ")
        }
        if let email, !email.isEmpty {
            return email
        }
        return "CareCircle Member"
    }
}
