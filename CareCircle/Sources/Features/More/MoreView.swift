import SwiftData
import SwiftUI

// MARK: - MoreView

struct MoreView: View {
    let authState: AuthState

    @Query(sort: \Circle.createdAt) private var circles: [Circle]

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id })
    }

    private var signedInAppleUserID: String {
        if case let .signedIn(user) = authState.status {
            return user.id
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            List {
                if let circle = activeCircle {
                    Section("Your Circle") {
                        NavigationLink {
                            CircleDetailView(circle: circle, signedInAppleUserID: signedInAppleUserID)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(circle.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.ccText)
                                if let recipient = circle.careRecipient {
                                    Text(recipient.fullName)
                                        .font(.footnote)
                                        .foregroundStyle(Color.ccSecondary)
                                }
                            }
                        }
                    }
                }

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
