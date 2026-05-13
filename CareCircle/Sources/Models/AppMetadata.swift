import Foundation
import SwiftData

// MARK: - AppMetadata

/// Placeholder model so the SwiftData container has a non-empty schema in Phase 1.
/// Phase 2 will replace this with real `Circle` / `CareRecipient` / `Member` models.
@Model
final class AppMetadata {
    var launchCount: Int
    var onboardingCompletedAt: Date?

    init(launchCount: Int = 0, onboardingCompletedAt: Date? = nil) {
        self.launchCount = launchCount
        self.onboardingCompletedAt = onboardingCompletedAt
    }
}
