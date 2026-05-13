import OSLog
import SwiftData
import SwiftUI

// MARK: - CareCircleApp

@main
struct CareCircleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authState: AuthState
    @State private var syncEngine: SyncEngine
    @State private var sosCenter = SOSCenter()
    @State private var simplifiedPreference = SimplifiedModePreference()

    let modelContainer: ModelContainer
    let apiClient: APIClient
    let backendAuthService: BackendAuthService

    init() {
        let container = Self.makeModelContainer()
        modelContainer = container

        let client = APIClient(configuration: BackendConfiguration.resolveFromBundle())
        apiClient = client
        let authService = BackendAuthService(apiClient: client)
        backendAuthService = authService
        let engine = SyncEngine(apiClient: client, modelContainer: container)
        _syncEngine = State(initialValue: engine)
        _authState = State(initialValue: AuthState(
            backendAuthService: authService,
            syncEngine: engine
        ))

        MainActor.assumeIsolated {
            MedicationServices.shared.install(modelContainer: container)
        }
    }

    private static func makeModelContainer() -> ModelContainer {
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
            PendingOperation.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(CloudKitConfiguration.containerIdentifier)
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            AppLogger.persistence.critical(
                "Failed to initialize ModelContainer: \(error.localizedDescription, privacy: .public)"
            )
            fatalError("Unable to initialize SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(authState: authState)
                .environment(\.circleSharingService, CircleSharingService.shared)
                .environment(sosCenter)
                .environment(simplifiedPreference)
                .environment(syncEngine)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
