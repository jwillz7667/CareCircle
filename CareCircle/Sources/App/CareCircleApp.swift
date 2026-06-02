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
    @State private var healthRecordsImporter = HealthRecordsImporter()
    @State private var locationService: LocationSharingService
    @State private var insightsEngine = InsightsEngine()
    @State private var sosCenter: SOSCenter
    @State private var simplifiedPreference = SimplifiedModePreference()
    @State private var subscriptionService: SubscriptionService
    @State private var pushRegistration: PushRegistrationService

    /// `BackendDocumentService` is an actor, so it isn't itself
    /// observable. The sweeper owns it; only the sweeper is exposed
    /// to views.
    private let documentService: BackendDocumentService

    let modelContainer: ModelContainer
    let apiClient: APIClient
    let backendAuthService: BackendAuthService

    /// `UserDefaults` is wiped when iOS deletes the app, but Keychain
    /// entries written with `AccessibleAfterFirstUnlockThisDeviceOnly`
    /// survive uninstall. After a reinstall we'd otherwise auto-sign-in
    /// from a credential the user thought they cleared. Flipping this
    /// flag the first time the new install runs lets us purge those
    /// orphaned credentials before `AuthState.bootstrap()` reads them.
    private static let didLaunchBeforeKey = "com.jwillz.carecircle.didLaunchBefore"

    init() {
        Self.purgeAuthOnFreshInstall()

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
        let auth = AuthState(backendAuthService: authService, syncEngine: engine)
        _authState = State(initialValue: auth)
        _sosCenter = State(initialValue: SOSCenter(apiClient: client))
        _pushRegistration = State(initialValue: Self.makePushRegistration(apiClient: client, auth: auth))
        _realtimeClient = State(initialValue: BackendRealtimeClient(
            apiClient: client,
            configuration: configuration,
            currentBackendUserID: { [auth] in auth.lastVerifiedProfile?.id }
        ))
        _inferenceClient = State(initialValue: BackendInferenceClient(apiClient: client))
        _subscriptionService = State(initialValue: .init(apiClient: client, modelContainer: container))
        _healthKitReader = State(initialValue: HealthKitVitalsReader(
            syncEngine: engine,
            currentRecorderAppleUserID: { [auth] in
                if case let .signedIn(user) = auth.status { return user.id }
                return nil
            }
        ))
        _locationService = State(initialValue: LocationSharingService(
            modelContainer: container,
            currentAuthor: { [auth] in
                guard case let .signedIn(user) = auth.status else { return nil }
                return ActivityAuthorContext(appleUserID: user.id, displayName: user.displayName)
            }
        ))

        Self.installMedicationServices(into: container)
    }

    /// Bridges the backend auth state into the push service as a plain bool
    /// probe so the service stays decoupled from `AuthState`'s full surface.
    private static func makePushRegistration(
        apiClient: APIClient,
        auth: AuthState
    )
        -> PushRegistrationService
    {
        PushRegistrationService(apiClient: apiClient, isAuthenticated: { [auth] in
            if case .signedIn = auth.status { return true }
            return false
        })
    }

    private static func installMedicationServices(into container: ModelContainer) {
        MainActor.assumeIsolated {
            MedicationServices.shared.install(modelContainer: container)
        }
    }

    private static func purgeAuthOnFreshInstall() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didLaunchBeforeKey) else { return }
        let keychain = KeychainStore()
        try? keychain.delete(KeychainStore.signedInUserKey)
        try? keychain.delete(KeychainStore.backendTokensKey)
        defaults.set(true, forKey: didLaunchBeforeKey)
        AppLogger.auth.info("Fresh install detected — cleared cached auth credentials from prior install.")
    }

    /// Builds the SwiftData store with a recovery ladder rather than crashing
    /// on the first failure. CloudKit and the Railway backend are the record
    /// of truth, so a wiped or downgraded local store re-hydrates on next
    /// sync — locking the user out of the app is the worse outcome.
    ///
    /// 1. CloudKit-synced persistent store (normal path).
    /// 2. Same on-disk store with CloudKit disabled — covers iCloud account or
    ///    entitlement failures where the store itself is intact.
    /// 3. Delete the store and recreate it fresh — covers corruption or a
    ///    schema the migration plan can't bridge.
    /// 4. In-memory store so the app still launches this session.
    /// 5. `fatalError` only if even an in-memory store can't be created.
    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: CareCircleSchemaV1.self)
        let cloudKitConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(CloudKitConfiguration.containerIdentifier)
        )

        if let container = try? makeContainer(schema: schema, configuration: cloudKitConfiguration) {
            return container
        }

        let storeURL = cloudKitConfiguration.url
        AppLogger.persistence.critical(
            "CloudKit ModelContainer failed; retrying local-only at \(storeURL.path, privacy: .public)"
        )

        let localConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        if let container = try? makeContainer(schema: schema, configuration: localConfiguration) {
            return container
        }

        AppLogger.persistence.critical(
            "Local store unreadable; deleting and recreating at \(storeURL.path, privacy: .public)"
        )
        Self.deleteStoreFiles(at: storeURL)
        if let container = try? makeContainer(schema: schema, configuration: localConfiguration) {
            return container
        }

        AppLogger.persistence.fault("All persistent stores failed; falling back to in-memory store")
        let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? makeContainer(schema: schema, configuration: memoryConfiguration) {
            return container
        }

        fatalError("Unable to initialize any SwiftData ModelContainer")
    }

    private static func makeContainer(
        schema: Schema,
        configuration: ModelConfiguration
    ) throws
        -> ModelContainer
    {
        try ModelContainer(
            for: schema,
            migrationPlan: CareCircleMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Removes the SQLite store and its `-wal` / `-shm` sidecars. Best-effort:
    /// a missing file is the desired end state, so failures are ignored.
    private static func deleteStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        let base = storeURL.lastPathComponent
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(at: directory.appendingPathComponent(base + suffix))
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
                .environment(healthRecordsImporter)
                .environment(locationService)
                .environment(insightsEngine)
                .environment(subscriptionService)
                .environment(pushRegistration)
                .task {
                    appDelegate.pushTokenHandler = { [pushRegistration] token in
                        pushRegistration.handleDeviceToken(token)
                    }
                    appDelegate.pushFailureHandler = { [pushRegistration] error in
                        pushRegistration.registrationDidFail(error)
                    }
                    if case .signedIn = authState.status {
                        pushRegistration.registerForPushNotifications()
                    }
                }
                .onChange(of: authState.status) { _, status in
                    guard case .signedIn = status else { return }
                    pushRegistration.flushPendingRegistration()
                    pushRegistration.registerForPushNotifications()
                }
                .preferredColorScheme(.light)
        }
        .modelContainer(modelContainer)
    }
}
