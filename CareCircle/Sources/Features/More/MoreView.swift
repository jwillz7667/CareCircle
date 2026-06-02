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

    private var authorContext: ActivityAuthorContext {
        guard case let .signedIn(user) = authState.status else {
            return ActivityAuthorContext(appleUserID: "", displayName: "")
        }
        return ActivityAuthorContext(appleUserID: user.id, displayName: user.displayName)
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

                    Section("Care planning") {
                        NavigationLink {
                            AppointmentListView(circle: circle)
                        } label: {
                            Label("Calendar", systemImage: "calendar")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            ShiftDigestListView(circle: circle, author: authorContext)
                        } label: {
                            Label("Shift digests", systemImage: "waveform.path.ecg")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            CaregiverLoadView(circle: circle)
                        } label: {
                            Label("Care load", systemImage: "person.3.sequence.fill")
                                .foregroundStyle(Color.ccText)
                        }
                    }

                    Section("Records") {
                        NavigationLink {
                            PulseDashboardView(authState: authState)
                        } label: {
                            Label("Pulse", systemImage: "sparkles")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            InsightsView(circle: circle, author: authorContext)
                        } label: {
                            Label("Insights", systemImage: "lightbulb.max")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            JournalListView(circle: circle, author: authorContext)
                        } label: {
                            Label("Symptom journal", systemImage: "note.text")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            VitalsListView(circle: circle, author: authorContext)
                        } label: {
                            Label("Vitals history", systemImage: "list.bullet.rectangle")
                                .foregroundStyle(Color.ccText)
                        }

                        NavigationLink {
                            HealthRecordsView(circle: circle)
                        } label: {
                            Label("Health Records (Apple Health)", systemImage: "heart.text.square")
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
                    }

                    Section("Safety") {
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

                        NavigationLink {
                            CircleMapView(authState: authState)
                        } label: {
                            Label("Find on map", systemImage: "location.fill.viewfinder")
                                .foregroundStyle(Color.ccText)
                        }
                    }
                }

                Section("Account") {
                    if case let .signedIn(user) = authState.status {
                        LabeledContent("Signed in as", value: user.displayName)
                            .foregroundStyle(Color.ccText)
                    }

                    if let circle = activeCircle {
                        NavigationLink {
                            SubscriptionStatusView(
                                circle: circle,
                                viewerAppleUserID: signedInAppleUserID
                            )
                        } label: {
                            HStack {
                                Label("Subscription", systemImage: "creditcard")
                                    .foregroundStyle(Color.ccText)
                                Spacer()
                                Text(circle.subscriptionTier.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.ccSecondary)
                            }
                        }
                    }

                    NavigationLink {
                        AccountPrivacyView(authState: authState)
                    } label: {
                        Label("Account & Privacy", systemImage: "lock.shield")
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

                    if let supportURL = URL(string: "mailto:support@viral-ventures-llc.com") {
                        Link(destination: supportURL) {
                            Label("Help & Support", systemImage: "envelope")
                                .foregroundStyle(Color.ccPrimary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    BrandLogo(size: 28)
                }
            }
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
