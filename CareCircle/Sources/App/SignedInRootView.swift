import SwiftData
import SwiftUI

// MARK: - SignedInRootView

/// Wraps `MainTabView` and switches it out for `SimplifiedHomeView`
/// whenever the simplified-mode preference is active for the current
/// viewer. Owns the @Query that resolves the active Circle so that
/// `RootView` stays focused on auth state.
struct SignedInRootView: View {
    let authState: AuthState
    let user: SignedInUser

    @Environment(SimplifiedModePreference.self) private var simplifiedPreference
    @Query(sort: \Circle.createdAt) private var circles: [Circle]

    private var activeCircle: Circle? {
        circles.first(where: { $0.ownerAppleUserID == user.id }) ?? circles.first
    }

    private var viewerRole: MemberRole? {
        activeCircle?
            .members
            .first(where: { $0.appleUserID == user.id })?
            .role
    }

    var body: some View {
        if simplifiedPreference.effectiveIsActive(viewerRole: viewerRole) {
            SimplifiedHomeView(
                authState: authState,
                circle: activeCircle,
                preference: simplifiedPreference
            )
        } else {
            MainTabView(authState: authState)
        }
    }
}
