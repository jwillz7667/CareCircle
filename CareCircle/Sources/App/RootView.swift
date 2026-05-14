import SwiftData
import SwiftUI

// MARK: - RootView

struct RootView: View {
    let authState: AuthState

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(BackendHydrator.self) private var hydrator
    @State private var didHydrateThisLaunch = false

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
                Task {
                    await authState.verifyBackendSession()
                    await maybeHydrateOnce()
                }
            }
        }
    }

    private func maybeHydrateOnce() async {
        guard !didHydrateThisLaunch,
              isSignedIn,
              authState.lastVerifiedProfile != nil else { return }
        didHydrateThisLaunch = true
        hydrator.triggerHydrateAll(modelContext: modelContext)
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
