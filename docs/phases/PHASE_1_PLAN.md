# Phase 1 — Skeleton + Sign in with Apple + empty tabs

## Goal

The app launches, the user can sign in with Apple, and lands on a four-tab interface (Home / Today / Meds / More) with empty states. The SwiftData container is initialized with a placeholder schema, and the CloudKit container is wired in entitlements but unused by SwiftData yet.

## Files to create

Under `CareCircle/Sources/` (synchronized into the app target automatically).

### App
- `App/CareCircleApp.swift` — `@main`, instantiates `ModelContainer`, owns the `AuthState`, drives launch-time bootstrap.
- `App/RootView.swift` — auth gate; switches between a launch-loading view, `SignInView`, and `MainTabView` based on `AuthState.status`.
- `App/MainTabView.swift` — four-tab TabView (Home / Today / Meds / More) using SF Symbols.

### Features/Auth
- `Features/Auth/AuthStatus.swift` — `enum AuthStatus { unknown, signedOut, signedIn(SignedInUser) }`.
- `Features/Auth/SignedInUser.swift` — `Codable` value type wrapping the Apple credential's stable user identifier plus given name / family name / email.
- `Features/Auth/AuthError.swift` — typed errors for the auth flow.
- `Features/Auth/AuthState.swift` — `@Observable @MainActor` controller; owns `status`, performs launch bootstrap (verify Apple credential state, restore Keychain user), handles sign-in completion and sign-out.
- `Features/Auth/KeychainStore.swift` — small `Sendable` wrapper over the Security framework. Stores the encoded `SignedInUser` keyed by service ID.
- `Features/Auth/SignInView.swift` — welcome / onboarding-card layout that uses `SignInWithAppleButton`, generates a SHA256-hashed nonce, hands the credential to `AuthState`.

### Features/Home, Today, Meds, More
- `Features/Home/HomeView.swift` — empty state: "Welcome to CareCircle" hero + "Record your first handoff" prompt placeholder.
- `Features/Today/TodayView.swift` — empty state: "Nothing scheduled".
- `Features/Meds/MedsView.swift` — empty state + the mandated `DisclaimerFooter`.
- `Features/More/MoreView.swift` — sign-out button (uses `AuthState`), version row, future-settings placeholder.

### DesignSystem
- `DesignSystem/SageTheme.swift` — `Color` extensions for the spec's sage / cream / navy palette plus a `Theme` namespace.
- `DesignSystem/EmptyStateView.swift` — reusable SF Symbol + headline + body component.
- `DesignSystem/DisclaimerFooter.swift` — "Not medical advice — consult your healthcare provider" footer used on med-related screens.

### Models
- `Models/AppMetadata.swift` — minimal SwiftData `@Model` so the container has a valid schema. Phase 2 will replace with real `Circle` / `CareRecipient` / `Member` models.

### Core
- `Core/AppLogger.swift` — `os.Logger` categories: `app`, `auth`, `persistence`.

## Files to delete

The Xcode template stubs become unreachable once `App/CareCircleApp.swift` replaces them:

- `CareCircle/CareCircleApp.swift`
- `CareCircle/ContentView.swift`
- `CareCircle/Item.swift`

## Files to modify

None. Entitlements were updated in Phase 0.

## Data model changes

Single `@Model AppMetadata` with two fields (`launchCount: Int`, `onboardingCompletedAt: Date?`). Used to prove the container is live. Real models start in Phase 2.

## Public API surface

```swift
// AuthStatus.swift
enum AuthStatus: Sendable, Equatable {
    case unknown
    case signedOut
    case signedIn(SignedInUser)
}

// SignedInUser.swift
struct SignedInUser: Sendable, Equatable, Identifiable, Codable {
    let id: String
    let givenName: String?
    let familyName: String?
    let email: String?
    var displayName: String { get }
}

// AuthError.swift
enum AuthError: LocalizedError, Sendable {
    case canceled
    case invalidCredential
    case credentialRevoked
    case keychainFailure(OSStatus)
    case unknown(String)
}

// AuthState.swift
@Observable @MainActor final class AuthState {
    private(set) var status: AuthStatus
    init(keychain: KeychainStore = .init(service: "Res.CareCircle.auth"))
    func bootstrap() async
    func completeAppleSignIn(result: Result<ASAuthorization, Error>, expectedNonce: String) async
    func signOut()
}

// KeychainStore.swift
struct KeychainStore: Sendable {
    let service: String
    func set(_ data: Data, forKey key: String) throws(KeychainError)
    func data(forKey key: String) throws(KeychainError) -> Data?
    func delete(_ key: String) throws(KeychainError)
}

// DesignSystem
extension Color {
    static let ccPrimary: Color         // sage green per spec C1
    static let ccBackground: Color      // warm cream
    static let ccText: Color            // deep navy
    static let ccSecondary: Color
    static let ccDanger: Color
}
```

## Test plan

No automated tests this phase — there is no test target yet, and creating one is a manual Xcode step. Test debt is documented in `docs/known_issues.md`. The auth flow is structured around protocol-free concrete types for Phase 1 simplicity; Phase 2 will introduce a protocol on Sign-in if a test target lands.

Manual verification (after the user opens Xcode and runs ⌘R):

1. App launches → brief launch view → welcome screen with **Sign in with Apple** button.
2. Tap the button → Apple's sheet appears → complete authentication.
3. Land on Home tab (empty state, "Welcome to CareCircle").
4. Tap each tab — Today, Meds (with disclaimer footer), More — all render empty states.
5. Tap **Sign Out** in More → returns to welcome screen.
6. Sign in again → relaunch the app → lands directly on Home (Keychain-restored).

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Sign in with Apple fails on Simulator without an iCloud account | Test on a Simulator that has an Apple ID configured, or on a real device. Surface clear error UX. |
| Keychain access at first unlock returns `errSecInteractionNotAllowed` | Use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so keychain is readable after device unlock. |
| Race between `AuthState.bootstrap()` (async) and view rendering | Render `.unknown` as a quiet launch view; only transition once bootstrap completes. |
| Apple returns name/email only on first sign-in | Persist them to Keychain on the first completion; never overwrite with `nil` on subsequent sign-ins. |
| SwiftData ModelContainer init fatal-errors | Acceptable: container failure means the app is unusable, so crashing surfaces the bug to the developer. Spec template uses the same pattern. |
| iOS 26 deployment target excludes most testers | Recorded in known issues; lower to iOS 17 in Xcode before TestFlight. |

## Definition of Done

1. App builds with `xcodebuild` cleanly (exit 0, zero warnings introduced).
2. The three Xcode template stubs (`CareCircleApp.swift` at root, `ContentView.swift`, `Item.swift`) are deleted.
3. The new `Sources/App/CareCircleApp.swift` declares the single `@main`.
4. `AuthState` starts as `.unknown`, transitions to `.signedOut` or `.signedIn` after `bootstrap()`.
5. `SignInWithAppleButton` is the only sign-in affordance; tapping it produces a credential and persists it via `KeychainStore`.
6. Four tabs render with SF Symbol icons (`house.fill`, `list.bullet.clipboard.fill`, `pills.fill`, `ellipsis.circle.fill`) and the spec's sage-tint color.
7. Meds tab shows a medical-advice disclaimer footer.
8. More tab can sign the user out.
9. Relaunching the app after sign-in skips the welcome screen.
10. CLAUDE.md gotchas section updated if anything new surfaces.

## Self-critique

Three weakest decisions in this plan, scrubbed for the kind of thing a Staff Engineer would catch on review:

1. **No protocol abstraction on Apple Sign in.** With no test target, I'm shipping `AuthState` that calls Apple's API directly. Justification: testing is deferred; introducing a protocol now would be premature abstraction per quality bar rule 11. Risk: when tests land in Phase 2+, this needs a small refactor. Accepted.

2. **`AppMetadata` placeholder model is dead-weight.** It exists only to give SwiftData a non-empty schema. The alternative — defining real `Circle` / `CareRecipient` models now and not wiring them up — would be the same dead-weight in disguise, plus harder to delete cleanly. The lesser-evil placeholder gets thrown away in Phase 2 commit.

3. **Bootstrap race window is handled by an `.unknown` initial state, not a true loading splash.** When the launch view shows, `AuthState.bootstrap()` is racing the first render. The user might see a one-frame flash before the welcome screen appears. Acceptable for Phase 1; a proper launch screen lands in Phase 12 polish.

Two places where I might be over- or under-engineered:

- **Under-engineered:** No retry / backoff on `getCredentialState`. If Apple's servers are flaky, the bootstrap call fails once and we land on the welcome screen. Phase 1 doesn't need retry, but the user might re-tap the button — acceptable UX for an MVP.
- **Maybe over-engineered:** Typed `KeychainError` throwing rather than just optional returns. But quality bar 5 mandates typed errors at boundaries, and Keychain IS a system boundary. Keeping it.

One thing a future engineer might curse me for:

- The Apple user identifier is stored in Keychain by a service string literal `"Res.CareCircle.auth"`. Constants should live in one place. I'll put the service string on `KeychainStore` itself rather than spreading it. Done in the implementation.
