import CloudKit
import Foundation

// MARK: - CircleSharePayload

struct CircleSharePayload {
    let url: URL
    let share: CKShare
    let container: CKContainer
    let participantRoleHint: MemberRole

    var shareTitle: String {
        share[CKShare.SystemFieldKey.title] as? String ?? "Join my Circle"
    }
}
