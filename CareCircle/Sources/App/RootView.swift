import SwiftUI

// MARK: - RootView

struct RootView: View {
    let authState: AuthState

    var body: some View {
        Group {
            switch authState.status {
            case .unknown:
                LaunchView()
            case .signedOut:
                SignInView(authState: authState)
            case .signedIn:
                MainTabView(authState: authState)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSignedIn)
        .task {
            if authState.status == .unknown {
                await authState.bootstrap()
            }
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
