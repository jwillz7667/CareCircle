import SwiftData
import SwiftUI

// MARK: - RootView

struct RootView: View {
    let authState: AuthState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(BackendHydrator.self) private var hydrator
    @Environment(BackendDocumentRetrySweeper.self) private var documentSweeper
    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @Environment(InsightsEngine.self) private var insightsEngine
    @Environment(HealthKitVitalsReader.self) private var healthKitReader
    @Environment(HealthRecordsImporter.self) private var healthRecordsImporter
    @Environment(SubscriptionService.self) private var subscriptionService
    @State private var didHydrateThisLaunch = false
    @State private var didStartSubscriptionsThisLaunch = false
    @State private var didRequestHealthKitAuth = false
    @State private var didImportClinicalThisLaunch = false

    var body: some View {
        Group {
            switch authState.status {
            case .unknown:
                LaunchView()
            case .signedOut:
                SignInView(authState: authState)
            case let .signedIn(user):
                SignedInRootView(authState: authState, user: user)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSignedIn)
        .task {
            if authState.status == .unknown {
                await authState.bootstrap()
            }
            await maybeHydrateOnce()
        }
        .onChange(of: authState.lastVerifiedProfile) { _, _ in
            Task { await maybeHydrateOnce() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, isSignedIn {
                MedicationOverdueSweeper().sweep(in: modelContext)
                documentSweeper.triggerSweep(modelContext: modelContext)
                documentSweeper.triggerPrefetch(modelContext: modelContext)
                realtimeClient.start(modelContext: modelContext)
                recomputeInsightsForAllCircles()
                Task {
                    await authState.verifyBackendSession()
                    await maybeHydrateOnce()
                    await readHealthKitForAllCircles()
                    await hydrateSubscriptionsForAllCircles()
                }
            } else if newPhase == .background || newPhase == .inactive {
                realtimeClient.stop()
            }
        }
    }

    private func maybeHydrateOnce() async {
        guard !didHydrateThisLaunch,
              isSignedIn,
              authState.lastVerifiedProfile != nil else { return }
        didHydrateThisLaunch = true
        hydrator.triggerHydrateAll(modelContext: modelContext)
        documentSweeper.triggerSweep(modelContext: modelContext)
        await pullDocumentKeys()
        documentSweeper.triggerPrefetch(modelContext: modelContext)
        realtimeClient.start(modelContext: modelContext)
        recomputeInsightsForAllCircles()
        await maybeStartSubscriptions()
        await hydrateSubscriptionsForAllCircles()
        await maybeRequestHealthKitAuth()
        await readHealthKitForAllCircles()
        await maybeImportClinicalRecordsOnce()
    }

    /// Boots the StoreKit transaction-updates listener exactly once per
    /// process. We don't tear it down on sign-out — Apple may post an
    /// external transaction at any time (renewal, refund, family share)
    /// and the listener's only job is to forward to the backend, which
    /// will reject without auth.
    private func maybeStartSubscriptions() async {
        guard !didStartSubscriptionsThisLaunch else { return }
        didStartSubscriptionsThisLaunch = true
        subscriptionService.start()
    }

    /// Pulls the backend's authoritative subscription state for every
    /// local Circle. Non-owner devices rely on this — they never see
    /// StoreKit events for someone else's purchase.
    private func hydrateSubscriptionsForAllCircles() async {
        let descriptor = FetchDescriptor<Circle>(sortBy: [SortDescriptor(\.createdAt)])
        let circleIDs = (try? modelContext.fetch(descriptor))?.map(\.id) ?? []
        for circleID in circleIDs {
            await subscriptionService.hydrate(circleID: circleID)
        }
    }

    /// Asks the user once per app install (we re-prompt on every launch
    /// only because HK silently no-ops after the first grant, which is
    /// the right outcome — the OS sheet only ever appears once per
    /// (type, app) so there's no UX cost to calling it every time).
    private func maybeRequestHealthKitAuth() async {
        guard !didRequestHealthKitAuth, healthKitReader.isAvailable else { return }
        didRequestHealthKitAuth = true
        _ = try? await healthKitReader.requestAuthorizationIfNeeded()
    }

    private func readHealthKitForAllCircles() async {
        guard healthKitReader.isAvailable else { return }
        let descriptor = FetchDescriptor<Circle>(sortBy: [SortDescriptor(\.createdAt)])
        let circles = (try? modelContext.fetch(descriptor)) ?? []
        for circle in circles {
            await healthKitReader.readNewSamples(for: circle, modelContext: modelContext)
        }
    }

    /// Clinical records (MyChart / Epic) read is heavy compared to a
    /// vitals sweep — provider FHIR resources can be hundreds of KB each,
    /// and the records change at the cadence of clinic visits, not
    /// seconds. Run it at most once per cold launch; the user can pull-
    /// to-refresh the Health Records screen for ad-hoc imports.
    private func maybeImportClinicalRecordsOnce() async {
        guard !didImportClinicalThisLaunch, healthRecordsImporter.isAvailable else { return }
        didImportClinicalThisLaunch = true
        _ = try? await healthRecordsImporter.requestAuthorizationIfNeeded()
        let descriptor = FetchDescriptor<Circle>(sortBy: [SortDescriptor(\.createdAt)])
        let circles = (try? modelContext.fetch(descriptor)) ?? []
        guard let primary = circles.first else { return }
        await healthRecordsImporter.importAll(into: modelContext, circle: primary)
    }

    private func pullDocumentKeys() async {
        let descriptor = FetchDescriptor<Circle>(sortBy: [SortDescriptor(\.createdAt)])
        let circleIDs = (try? modelContext.fetch(descriptor))?.map(\.id) ?? []
        guard !circleIDs.isEmpty else { return }
        await CircleDocumentKeySyncService.shared.pullForAllCircles(circleIDs)
    }

    private func recomputeInsightsForAllCircles() {
        let descriptor = FetchDescriptor<Circle>(sortBy: [SortDescriptor(\.createdAt)])
        let circles = (try? modelContext.fetch(descriptor)) ?? []
        for circle in circles {
            insightsEngine.recompute(circle: circle, modelContext: modelContext)
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = authState.status {
            return true
        }
        return false
    }
}

// MARK: - LaunchView

private struct LaunchView: View {
    var body: some View {
        ZStack {
            Color.ccBackground.ignoresSafeArea()

            VStack(spacing: Theme.looseSpacing) {
                BrandLogo(size: 140)
                ProgressView()
                    .tint(Color.ccPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading CareCircle")
        }
    }
}
