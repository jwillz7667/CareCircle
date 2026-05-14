import Foundation
import SwiftData

// MARK: - ChatMessage

/// Single message posted to a Circle's Wall. Everyone in the Circle
/// reads the same chronological stream — there is one wall per Circle,
/// not per-member DMs. v1 keeps the model deliberately flat so that
/// CloudKit's shared zone can fan the rows out to every member without
/// any additional fanout logic on our side.
///
/// Reactions are intentionally omitted in v1. Long-press to edit/delete
/// is allowed only for the original author — server doesn't enforce
/// this in CloudKit; the iOS UI is the gate.
@Model
final class ChatMessage {
    var id = UUID()
    /// Snapshotted at write time so historical posts keep attribution
    /// even after a Member is renamed/removed.
    var authorAppleUserID = ""
    var authorDisplayName = ""
    /// 1–2 char emoji or SF Symbol name for the author chip. Optional —
    /// the UI falls back to initials.
    var authorAvatarEmoji = ""
    var body = ""
    /// "wall" = visible to whole circle; "system" = composed by the app
    /// (SOS broadcast, shift digest summary, etc.) and styled distinctly.
    var kindRaw = "wall"
    var createdAt = Date.now
    var editedAt: Date?

    var circle: Circle?

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .wall }
        set { kindRaw = newValue.rawValue }
    }

    enum Kind: String, Sendable {
        case wall, system
    }

    init(
        id: UUID = UUID(),
        authorAppleUserID: String,
        authorDisplayName: String,
        authorAvatarEmoji: String = "",
        body: String,
        kind: Kind = .wall,
        createdAt: Date = .now,
        editedAt: Date? = nil
    ) {
        self.id = id
        self.authorAppleUserID = authorAppleUserID
        self.authorDisplayName = authorDisplayName
        self.authorAvatarEmoji = authorAvatarEmoji
        self.body = body
        kindRaw = kind.rawValue
        self.createdAt = createdAt
        self.editedAt = editedAt
    }
}
