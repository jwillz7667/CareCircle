import OSLog
import SwiftData
import SwiftUI

// MARK: - CareCircleApp

@main
struct CareCircleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authState = AuthState()
    @State private var sosCenter = SOSCenter()
    @State private var simplifiedPreference = SimplifiedModePreference()

    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            Circle.self,
            CareRecipient.self,
            Member.self,
            Activity.self,
            ActivityReaction.self,
            ActivityComment.self,
            Medication.self,
            DoseEvent.self,
            Appointment.self,
            Document.self,
            SOSEvent.self,
            EmergencyContact.self,
            CareMinuteEntry.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(CloudKitConfiguration.containerIdentifier)
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            AppLogger.persistence.critical(
                "Failed to initialize ModelContainer: \(error.localizedDescription, privacy: .public)"
            )
            fatalError("Unable to initialize SwiftData ModelContainer: \(error)")
        }
        MainActor.assumeIsolated {
            MedicationServices.shared.install(modelContainer: modelContainer)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(authState: authState)
                .environment(\.circleSharingService, CircleSharingService.shared)
                .environment(sosCenter)
                .environment(simplifiedPreference)
        }
        .modelContainer(modelContainer)
    }
}
