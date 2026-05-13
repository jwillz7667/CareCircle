import Foundation
import SwiftData

// MARK: - MedicationServices

/// Holds references that the `CircleSceneDelegate` and `MedicationNotificationDelegate`
/// need without taking a hard dependency on the SwiftUI `@main` graph. The app
/// publishes its `ModelContainer` here at startup so out-of-band touch points
/// (push action handlers, scene delegate hooks) can resolve a `ModelContext`.
@MainActor
final class MedicationServices {
    static let shared = MedicationServices()

    private(set) var modelContainer: ModelContainer?
    private(set) var notificationDelegate: MedicationNotificationDelegate?

    private init() {}

    func install(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func install(notificationDelegate: MedicationNotificationDelegate) {
        self.notificationDelegate = notificationDelegate
    }

    func currentContainer() -> ModelContainer? {
        modelContainer
    }
}
