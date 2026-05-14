import SwiftData
import SwiftUI

// MARK: - ShiftDigestListView

/// Chronological list of shift digests for a single Circle. The
/// caregiver who's coming on shift opens this to catch up on the
/// previous narrator's handoff. Pull-to-refresh re-runs the realtime
/// snapshot pass against the Railway backend so a brand-new digest
/// from another device shows up without restarting the app.
struct ShiftDigestListView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @State private var isComposing = false

    private var permissions: CirclePermissions {
        CirclePermissions.resolve(circle: circle, appleUserID: author.appleUserID)
    }

    private var sortedDigests: [ShiftDigest] {
        circle.shiftDigests.sorted { $0.shiftEndAt > $1.shiftEndAt }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            scrollContent
            if permissions.canPostActivity {
                composerButton
                    .padding(.trailing, Theme.spacing)
                    .padding(.bottom, Theme.spacing)
            }
        }
        .background(Color.ccBackground)
        .navigationTitle("Shifts")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .sheet(isPresented: $isComposing) {
            ShiftDigestComposerView(circle: circle, author: author)
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                if sortedDigests.isEmpty {
                    emptyState
                        .padding(.top, Theme.looseSpacing)
                } else {
                    LazyVStack(spacing: Theme.spacing) {
                        ForEach(sortedDigests) { digest in
                            NavigationLink {
                                ShiftDigestDetailView(digest: digest, author: author)
                            } label: {
                                ShiftDigestRow(digest: digest, author: author)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.top, Theme.spacing)
            .padding(.bottom, 96)
        }
        .refreshable {
            await realtimeClient.snapshotResync(
                circleIds: [circle.id],
                modelContext: modelContext
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ccPrimary)
            Text("No shift digests yet.")
                .font(.headline)
                .foregroundStyle(Color.ccText)
            Text(permissions.canPostActivity
                ? "End-of-shift voice handoffs from your Circle will show up here."
                : "Handoffs from other caregivers will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.ccSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.looseSpacing)
        }
        .padding(.vertical, Theme.looseSpacing)
    }

    private var composerButton: some View {
        Button {
            isComposing = true
        } label: {
            Label("End shift", systemImage: "mic.fill")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
                .foregroundStyle(Color.white)
                .background(Capsule().fill(Color.ccPrimary))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
        }
        .accessibilityHint("Compose an end-of-shift voice digest.")
    }
}
