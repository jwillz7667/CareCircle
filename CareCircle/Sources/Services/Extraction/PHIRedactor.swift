import Foundation

// MARK: - PHIRedactor

/// Replaces care-recipient identifiers in transcript/body text with placeholders
/// before the text is sent to a language model. Per CARECIRCLE_SPEC §5.4, names
/// must not leave the device verbatim even when extraction runs on-device.
nonisolated struct PHIRedactor: Sendable {
    static let recipientPlaceholder = "[RECIPIENT]"
    static let caregiverPlaceholderPrefix = "[CAREGIVER_"

    let recipientFirstName: String?
    let recipientLastName: String?
    let caregiverDisplayNames: [String]

    init(
        recipientFirstName: String? = nil,
        recipientLastName: String? = nil,
        caregiverDisplayNames: [String] = []
    ) {
        self.recipientFirstName = recipientFirstName
        self.recipientLastName = recipientLastName
        self.caregiverDisplayNames = caregiverDisplayNames
    }

    init(circle: Circle, currentCaregiverDisplayName: String?) {
        let recipient = circle.careRecipient
        var caregivers: [String] = circle.members
            .map(\.displayName)
            .filter { !$0.isEmpty }
        if let current = currentCaregiverDisplayName, !current.isEmpty {
            caregivers.append(current)
        }
        self.init(
            recipientFirstName: recipient?.firstName,
            recipientLastName: recipient?.lastName,
            caregiverDisplayNames: Array(Set(caregivers))
        )
    }

    func redact(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var output = input

        for token in recipientTokens() {
            output = replace(token: token, in: output, with: Self.recipientPlaceholder)
        }

        for (offset, name) in caregiverDisplayNames.enumerated() {
            let placeholder = "\(Self.caregiverPlaceholderPrefix)\(offset + 1)]"
            for token in tokens(for: name) {
                output = replace(token: token, in: output, with: placeholder)
            }
        }

        return output
    }

    private func recipientTokens() -> [String] {
        var tokens: [String] = []
        if let first = recipientFirstName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !first.isEmpty
        {
            tokens.append(first)
        }
        if let last = recipientLastName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !last.isEmpty
        {
            tokens.append(last)
        }
        if let first = recipientFirstName, let last = recipientLastName,
           !first.isEmpty, !last.isEmpty
        {
            tokens.append("\(first) \(last)")
        }
        return tokens
    }

    private func tokens(for displayName: String) -> [String] {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parts = trimmed.split(separator: " ").map(String.init)
        var tokens: [String] = [trimmed]
        tokens.append(contentsOf: parts.filter { $0.count >= 3 })
        return tokens
    }

    private func replace(token: String, in input: String, with replacement: String) -> String {
        guard !token.isEmpty else { return input }
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }
        let range = NSRange(input.startIndex ..< input.endIndex, in: input)
        return regex.stringByReplacingMatches(
            in: input,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }
}
