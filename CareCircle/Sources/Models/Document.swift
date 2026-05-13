import Foundation
import SwiftData

// MARK: - Document

/// Encrypted document stored inside a Circle. The plaintext file bytes are
/// never persisted: `ciphertext`, `nonce`, and `tag` are produced by
/// `DocumentVault.seal(_:circleID:)` against the per-circle SymmetricKey.
/// SwiftData propagates `ciphertext` to CloudKit as a CKAsset when the blob
/// exceeds CloudKit's inline record threshold.
@Model
final class Document {
    var id = UUID()
    var title = ""
    var typeRaw: String = DocumentType.other.rawValue
    var mimeType = "application/octet-stream"
    var sizeBytes = 0
    var ciphertext = Data()
    var nonce = Data()
    var tag = Data()
    var issuedAt: Date?
    var expiresAt: Date?
    var visibilityRolesRaw: [String] = DocumentVisibility.defaultRoles.map(\.rawValue)
    var uploadedByAppleUserID = ""
    var uploadedByDisplayName = ""
    var createdAt = Date.now
    var updatedAt = Date.now
    var deletedAt: Date?

    var circle: Circle?

    var type: DocumentType {
        get { DocumentType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var visibilityRoles: [MemberRole] {
        get { visibilityRolesRaw.compactMap(MemberRole.init(rawValue:)) }
        set { visibilityRolesRaw = newValue.map(\.rawValue) }
    }

    init(
        id: UUID = UUID(),
        title: String,
        type: DocumentType,
        mimeType: String,
        sizeBytes: Int,
        ciphertext: Data,
        nonce: Data,
        tag: Data,
        issuedAt: Date? = nil,
        expiresAt: Date? = nil,
        visibilityRoles: [MemberRole] = DocumentVisibility.defaultRoles,
        uploadedByAppleUserID: String,
        uploadedByDisplayName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        typeRaw = type.rawValue
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        visibilityRolesRaw = visibilityRoles.map(\.rawValue)
        self.uploadedByAppleUserID = uploadedByAppleUserID
        self.uploadedByDisplayName = uploadedByDisplayName
        self.createdAt = createdAt
        updatedAt = createdAt
    }

    var isReadable: Bool {
        deletedAt == nil && !ciphertext.isEmpty && !nonce.isEmpty && !tag.isEmpty
    }
}

// MARK: - DocumentVisibility

enum DocumentVisibility {
    static let defaultRoles: [MemberRole] = [
        .owner,
        .familyMember,
        .paidFamily,
        .careRecipient,
    ]
}
