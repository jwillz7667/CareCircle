import Foundation
import OSLog
import SwiftData

// MARK: - Activity

@Model
final class Activity {
    var id = UUID()
    var authorAppleUserID = ""
    var authorDisplayName = ""
    var createdAt = Date.now
    var typeRaw: String = ActivityType.textNote.rawValue
    var body = ""

    @Attribute(.externalStorage)
    var photoData: Data?

    @Attribute(.externalStorage)
    var audioData: Data?

    var audioDurationSeconds: Double = 0

    var circle: Circle?

    @Relationship(deleteRule: .cascade, inverse: \ActivityReaction.activity)
    var reactions: [ActivityReaction] = []

    @Relationship(deleteRule: .cascade, inverse: \ActivityComment.activity)
    var comments: [ActivityComment] = []

    var type: ActivityType {
        get {
            if let known = ActivityType(rawValue: typeRaw) {
                return known
            }
            let observed = typeRaw
            AppLogger.persistence.error(
                "Unknown Activity type \(observed, privacy: .public); defaulting to .system"
            )
            return .system
        }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        authorAppleUserID: String,
        authorDisplayName: String,
        type: ActivityType,
        body: String = "",
        photoData: Data? = nil,
        audioData: Data? = nil,
        audioDurationSeconds: Double = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.authorAppleUserID = authorAppleUserID
        self.authorDisplayName = authorDisplayName
        typeRaw = type.rawValue
        self.body = body
        self.photoData = photoData
        self.audioData = audioData
        self.audioDurationSeconds = audioDurationSeconds
        self.createdAt = createdAt
    }
}
