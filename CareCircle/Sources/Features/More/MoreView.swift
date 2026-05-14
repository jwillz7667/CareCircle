import SwiftData
import SwiftUI

// MARK: - MoreView

struct MoreView: View {
    let authState: AuthState

    @Environment(SimplifiedModePreference.self) private var simplifiedPreference
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(BackendHydrator.self) private var hydrator
    @Environment(\.modelContext) private var modelContext
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

                        NavigationLink {
                            AppointmentListView(circle: circle)
                        } label: {
                            Label("Calendar", systemImage: "calendar")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            DocumentListView(circle: circle, viewerAppleUserID: signedInAppleUserID)
                        } label: {
                            Label("Documents", systemImage: "folder.fill")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            CareMinuteListView(circle: circle, viewerAppleUserID: signedInAppleUserID)
                        } label: {
                            Label("Care minutes", systemImage: "clock.badge.checkmark")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            EmergencyContactsView(circle: circle)
                        } label: {
                            Label("Emergency contacts", systemImage: "phone.badge.plus")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            SOSHistoryView(circle: circle, viewerAppleUserID: signedInAppleUserID)
                        } label: {
                            Label("SOS history", systemImage: "sos.circle")
                                .foregroundStyle(Color.ccText)
                        }
                    }
                }

                Section {
                    @Bindable var preferenceBinding = simplifiedPreference
                    Toggle(isOn: $preferenceBinding.isManualOverrideEnabled) {
                        Label("Simplified mode", systemImage: "rectangle.compress.vertical")
                            .foregroundStyle(Color.ccText)
                    }
                    .tint(Color.ccPrimary)
                    .accessibilityHint(
                        "Switches to a single-screen layout with big call/text buttons for the person being cared for."
                    )
                } header: {
                    Text("Accessibility")
                } footer: {
                    Text("Designed for the person being cared for. Big buttons, fewer screens, one-tap call to family.")
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

                Section("Backend sync") {
                    LabeledContent("Status", value: syncStatusLabel)
                        .foregroundStyle(Color.ccText)

                    LabeledContent("Session", value: sessionStatusLabel)
                        .foregroundStyle(sessionStatusColor)

                    if syncEngine.pendingCount > 0 {
                        LabeledContent("Pending", value: "\(syncEngine.pendingCount)")
                            .foregroundStyle(Color.ccText)
                    }

                    if let lastSync = syncEngine.lastSyncAt {
                        LabeledContent(
                            "Last sync",
                            value: lastSync.formatted(.relative(presentation: .named))
                        )
                        .foregroundStyle(Color.ccText)
                    }

                    if let lastError = syncEngine.lastError {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(Color.ccDanger)
                    }

                    if shouldShowRetry {
                        Button {
                            syncEngine.triggerDrain()
                        } label: {
                            Label("Retry sync now", systemImage: "arrow.clockwise")
                                .foregroundStyle(Color.ccPrimary)
                        }
                    }

                    LabeledContent("Last hydrate", value: hydrateStatusLabel)
                        .foregroundStyle(hydrator.lastError == nil ? Color.ccText : Color.ccDanger)

                    Button {
                        hydrator.triggerHydrateAll(modelContext: modelContext)
                    } label: {
                        Label(
                            hydrator.isRunning ? "Pulling from backend…" : "Pull from backend now",
                            systemImage: "arrow.down.circle"
                        )
                        .foregroundStyle(Color.ccPrimary)
                    }
                    .disabled(hydrator.isRunning)
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

    private var syncStatusLabel: String {
        switch syncEngine.status {
        case .idle:
            "Up to date"
        case .draining:
            "Syncing…"
        case .offline:
            "Waiting to sign in"
        case let .error(message):
            message
        }
    }

    private var sessionStatusLabel: String {
        if let profile = authState.lastVerifiedProfile {
            return "Verified as \(profile.displayName ?? "user")"
        }
        if authState.lastVerifyError != nil {
            return "Unverified — check connection"
        }
        return "Not yet verified"
    }

    private var sessionStatusColor: Color {
        if authState.lastVerifiedProfile != nil { return Color.ccText }
        if authState.lastVerifyError != nil { return Color.ccDanger }
        return Color.ccSecondary
    }

    private var shouldShowRetry: Bool {
        if case .error = syncEngine.status { return true }
        if syncEngine.pendingCount > 0, case .offline = syncEngine.status { return true }
        return false
    }

    private var hydrateStatusLabel: String {
        if let error = hydrator.lastError {
            return error
        }
        if let lastRun = hydrator.lastRunAt {
            return lastRun.formatted(.relative(presentation: .named))
        }
        return "Not yet pulled"
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
