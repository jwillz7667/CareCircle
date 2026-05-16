import SwiftData
import SwiftUI

// MARK: - HomeDashboardView

/// "Today" tab content. Reads as one composed surface, not a stack of
/// independent widgets. Sections appear in priority order:
///
/// 1. Header strip — recipient + status dot + tiny SOS pill.
/// 2. Upgrade banner — visible only to free-tier Circle owners.
/// 3. Pulse insight — synthesis voice from on-device intelligence
///    (placeholder until phase E lands; surfaces shape now, content later).
/// 4. Today's plan — next handful of doses + the next appointment.
/// 5. What changed — recent activity rolled up from the Brain.
/// 6. Quick capture FAB — the only verb on the screen.
///
/// Critical-action strip (missed life-critical doses, red-zone vitals)
/// will appear above Pulse once phase B / E generate the signals. It is
/// intentionally absent until then — empty placeholders erode trust.
///
/// Section subviews live in `HomeDashboardCards.swift`.
struct HomeDashboardView: View {
    let authState: AuthState
    @Binding var selectedTab: AppTab

    @Query(sort: \Circle.createdAt) private var circles: [Circle]
    @Environment(SOSCenter.self) private var sosCenter

    @State private var isPresentingCreate = false
    @State private var isPresentingSOSArm = false
    @State private var isPresentingSOSCountdown = false
    @State private var isComposingText = false
    @State private var isComposingVoice = false
    @State private var isComposingShiftDigest = false

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id }) ?? circles.first
    }

    private var signedInUser: SignedInUser? {
        if case let .signedIn(user) = authState.status { return user }
        return nil
    }

    private var authorContext: ActivityAuthorContext {
        guard let user = signedInUser else {
            return ActivityAuthorContext(appleUserID: "", displayName: "")
        }
        return ActivityAuthorContext(appleUserID: user.id, displayName: user.displayName)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Today")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(Color.ccBackgroundPrimary, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        BrandLogo(size: 28)
                    }
                }
        }
        .sheet(isPresented: $isPresentingCreate) {
            CreateCircleView(authState: authState)
        }
        .sheet(isPresented: $isPresentingSOSArm) {
            sosArmSheet
        }
        .fullScreenCover(isPresented: $isPresentingSOSCountdown) {
            if let circle = activeCircle, let user = signedInUser {
                SOSCountdownView(circle: circle, user: user, center: sosCenter)
                    .onDisappear { sosCenter.reset() }
            }
        }
        .sheet(isPresented: $isComposingText) {
            if let circle = activeCircle {
                ActivityComposerView(circle: circle, author: authorContext)
            }
        }
        .sheet(isPresented: $isComposingVoice) {
            if let circle = activeCircle {
                VoiceComposerView(circle: circle, author: authorContext)
            }
        }
        .sheet(isPresented: $isComposingShiftDigest) {
            if let circle = activeCircle {
                ShiftDigestComposerView(circle: circle, author: authorContext)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let circle = activeCircle {
            populated(circle: circle)
        } else {
            empty
        }
    }

    private var empty: some View {
        ZStack(alignment: .bottom) {
            EmptyStateView(
                systemImage: "house.fill",
                title: "Welcome to CareCircle",
                message: "Create your Circle to begin coordinating care with family."
            )

            Button {
                isPresentingCreate = true
            } label: {
                Label("Create your Circle", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.ccPrimary)
            .padding(.horizontal, Spacing.l)
            .padding(.bottom, Spacing.l)
        }
    }

    private func populated(circle: Circle) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HomeHeaderStrip(circle: circle) {
                        isPresentingSOSArm = true
                    }

                    UpgradeBanner(circle: circle, viewerAppleUserID: signedInUser?.id ?? "")

                    HomePulseInsightCard()

                    HomeTodaysPlanCard(circle: circle) {
                        selectedTab = .meds
                    }

                    HomeWhatChangedCard(circle: circle) {
                        selectedTab = .brain
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
            }
            .background(Color.ccBackgroundPrimary)

            HomeQuickCaptureFAB(
                onNote: { isComposingText = true },
                onVoice: { isComposingVoice = true },
                onDigest: { isComposingShiftDigest = true }
            )
            .padding(.trailing, Spacing.m)
            .padding(.bottom, Spacing.m)
        }
    }

    private var sosArmSheet: some View {
        VStack(spacing: Spacing.l) {
            VStack(spacing: Spacing.xs) {
                Text("Arm SOS")
                    .font(.CC.titleMedium)
                    .foregroundStyle(Color.ccTextPrimary)
                Text(
                    "Hold the button for 3 seconds. A 30-second countdown starts so you can cancel an accidental trigger."
                )
                .font(.CC.caption)
                .foregroundStyle(Color.ccTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(Typography.lineSpacingDefault)
            }

            SOSTriggerButton(isAvailable: signedInUser != nil) {
                isPresentingSOSArm = false
                isPresentingSOSCountdown = true
            }

            Button("Cancel") {
                isPresentingSOSArm = false
            }
            .font(.CC.bodyEmphasized)
            .tint(Color.ccAccent)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity)
        .background(Color.ccBackgroundPrimary)
        .presentationDetents([.height(300)])
    }
}
