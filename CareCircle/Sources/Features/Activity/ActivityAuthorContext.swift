import Foundation

// MARK: - ActivityAuthorContext

/// Snapshot of the signed-in user used when stamping new Activities, reactions, and comments.
///
/// Activities denormalize `authorAppleUserID` + `authorDisplayName` so that historical posts
/// stay attributable even after a Member is renamed or removed.
struct ActivityAuthorContext: Hashable, Sendable {
    let appleUserID: String
    let displayName: String

    var hasIdentity: Bool {
        !appleUserID.isEmpty
    }
}
