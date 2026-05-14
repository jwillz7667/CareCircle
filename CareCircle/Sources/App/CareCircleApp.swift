import OSLog
import SwiftData
import SwiftUI

// MARK: - CareCircleApp

@main
struct CareCircleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var authState: AuthState
    @State private var syncEngine: SyncEngine
    @State private var hydrator: BackendHydrator
    @State private var documentSweeper: BackendDocumentRetrySweeper
    @State private var realtimeClient: BackendRealtimeClient
    @State private var inferenceClient: BackendInferenceClient
    @State private var healthKitReader: HealthKitVitalsReader
    @State private var locationService: LocationSharingService
    @State private var insightsEngine = InsightsEngine()
    @State private var sosCenter = SOSCenter()
    @State private var simplifiedPreference = SimplifiedModePreference()

    /// `BackendDocumentService` is an actor, so it isn't itself
    /// observable. The sweeper owns it; only the sweeper is exposed
    /// to views.
    private let documentService: BackendDocumentService

    let modelContainer: ModelContainer
    let apiClient: APIClient
    let backendAuthService: BackendAuthService

    init() {
        let container = Self.makeModelContainer()
        modelContainer = container

        let configuration = BackendConfiguration.resolveFromBundle()
        let client = APIClient(configuration: configuration)
        apiClient = client
        let authService = BackendAuthService(apiClient: client)
        backendAuthService = authService
        let engine = SyncEngine(apiClient: client, modelContainer: container)
        _syncEngine = State(initialValue: engine)
        _hydrator = State(initialValue: BackendHydrator(apiClient: client))
        let docService = BackendDocumentService(apiClient: client)
        documentService = docService
        _documentSweeper = State(initialValue: BackendDocumentRetrySweeper(service: docService))
        let auth = AuthState(
            backendAuthService: authService,
            syncEngine: engine
        )
        _authState = State(initialValue: auth)
        _realtimeClient = State(initialValue: BackendRealtimeClient(
            apiClient: client,
            configuration: configuration,
            currentBackendUserID: { [auth] in auth.lastVerifiedProfile?.id }
        ))
        _inferenceClient = State(initialValue: BackendInferenceClient(apiClient: client))
        _healthKitReader = State(initialValue: HealthKitVitalsReader(
            syncEngine: engine,
            currentBackendUserID: { [auth] in auth.lastVerifiedProfile?.id }
        ))
        _locationService = State(initialValue: LocationSharingService(
            modelContainer: container,
            currentAuthor: { [auth] in
                guard case let .signedIn(user) = auth.status else { return nil }
                return ActivityAuthorContext(appleUserID: user.id, displayName: user.displayName)
            }
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
            ShiftDigest.self,
            Insight.self,
            Vital.self,
            LocationSnapshot.self,
            ChatMessage.self,
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
                .environment(hydrator)
                .environment(documentSweeper)
                .environment(realtimeClient)
                .environment(inferenceClient)
                .environment(healthKitReader)
                .environment(locationService)
                .environment(insightsEngine)
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
