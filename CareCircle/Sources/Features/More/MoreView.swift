import SwiftUI

// MARK: - MoreView

struct MoreView: View {
    let authState: AuthState

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if case let .signedIn(user) = authState.status {
                        LabeledContent("Signed in as", value: user.displayName)
                            .foregroundStyle(Color.ccText)
                    }

                    Button(role: .destructive) {
                        authState.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .foregroundStyle(Color.ccDanger)
                }

                Section("About") {
                    LabeledContent("Version", value: Self.appVersion)
                        .foregroundStyle(Color.ccText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
