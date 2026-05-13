import Foundation
import SwiftData

// MARK: - ActivityComment

@Model
final class ActivityComment {
    var id = UUID()
    var body = ""
    var authorAppleUserID = ""
    var authorDisplayName = ""
    var createdAt = Date.now

    var activity: Activity?

    init(
        id: UUID = UUID(),
        body: String,
        authorAppleUserID: String,
        authorDisplayName: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.body = body
        self.authorAppleUserID = authorAppleUserID
        self.authorDisplayName = authorDisplayName
        self.createdAt = createdAt
    }
}
