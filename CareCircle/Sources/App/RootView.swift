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
    @State private var didHydrateThisLaunch = false
    @State private var didRequestHealthKitAuth = false

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
        await maybeRequestHealthKitAuth()
        await readHealthKitForAllCircles()
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

            VStack(spacing: Theme.spacing) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(Color.ccPrimary)
                ProgressView()
                    .tint(Color.ccPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading CareCircle")
        }
    }
}
