import Foundation
import SwiftData

// MARK: - ActivityReaction

@Model
final class ActivityReaction {
    var id = UUID()
    var emoji = "👍"
    var authorAppleUserID = ""
    var authorDisplayName = ""
    var createdAt = Date.now

    var activity: Activity?

    init(
        id: UUID = UUID(),
        emoji: String,
        authorAppleUserID: String,
        authorDisplayName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.emoji = emoji
        self.authorAppleUserID = authorAppleUserID
        self.authorDisplayName = authorDisplayName
        self.createdAt = createdAt
    }
}
