import Foundation

// MARK: - DocumentDraft

/// Scratchpad mirroring the editable metadata for a new Document. The byte
/// payload (plaintext) is held separately because we never want to keep it
/// inside an `Equatable` SwiftUI state value that diff-compares its
/// contents.
struct DocumentDraft: Equatable {
    var title = ""
    var type: DocumentType = .other
    var issuedAt: Date?
    var expiresAt: Date?
    var visibilityRoles: Set<MemberRole> = Set(DocumentVisibility.defaultRoles)
    var mimeType = ""
    var sourceFilename = ""
    var sizeBytes = 0

    init() {}

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedTitle.isEmpty &&
            !mimeType.isEmpty &&
            sizeBytes > 0 &&
            sizeBytes <= DocumentDraft.maxSizeBytes &&
            !visibilityRoles.isEmpty
    }

    static let maxSizeBytes = 10 * 1_024 * 1_024
    static let allowedMimeTypes: Set = [
        "image/jpeg",
        "image/png",
        "image/heic",
        "application/pdf",
    ]
}
