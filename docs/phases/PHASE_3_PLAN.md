# Phase 3 — Members + CKShare invitations

## Goal

The Circle owner can:
1. Open the Members section of their Circle.
2. Tap **Invite** → choose a role + display-name → produce a `CKShare` for the Circle.
3. Pass that share via the system share sheet (iMessage / Mail / copy link).

The invitee (on a real device, signed into iCloud) can:
1. Tap the share URL.
2. The app launches via `windowScene(_:userDidAcceptCloudKitShareWith:)` and accepts the share against the participant's iCloud account.
3. After the next sync round-trip the Circle appears in their app.

The 8-member cap is enforced at the validation layer (the Invite form blocks before issuing the share).

## Scope reality check (read this first)

Two architectural truths shape Phase 3:

1. **SwiftData + CKShare is not a one-liner.** SwiftData on iOS 26 wraps `NSPersistentCloudKitContainer`, so the private-database half of sync is free once we set `ModelConfiguration(cloudKitDatabase: .private("iCloud.Res.CareCircle"))`. Sharing, however, requires direct CKShare handling because SwiftData does not yet expose `share(_:to:)` as a public API.
2. **CKShare URLs do not resolve on the Simulator.** Per the gotcha already captured in `CLAUDE.md`, full end-to-end share acceptance requires two physical devices each signed into a distinct iCloud account. Phase 3 makes the build succeed cleanly, exercises every Simulator-testable path, and documents the real-device test matrix in `docs/cloudkit_testing.md`.

Given that, Phase 3 ships:

- A CloudKit-ready SwiftData schema (no `@Attribute(.unique)`, defaults everywhere).
- CloudKit private database sync via `ModelConfiguration`.
- A `CircleSharingService` that creates a CKShare for a Circle by mirroring the Circle UUID into a custom `CKRecordZone` in the owner's private database, builds a `CKShare`, and returns a URL + presentation handle.
- A `UISceneDelegate` adaptor that accepts incoming shares and inserts the resulting `Member`/`Circle` mirror into SwiftData.
- `MembersListView` + `AddMemberView` UI, hooked from `CircleDetailView`.
- A docs/cloudkit_testing.md runbook.

## Files to create

Under `CareCircle/Sources/`.

### Models
- *(no new model files; `Member` is extended in place — see §"Data model changes")*

### Services/CloudKit
- `Services/CloudKit/CloudKitConfiguration.swift` — Centralizes the container identifier and zone-name helpers so we don't sprinkle string literals across the code.
- `Services/CloudKit/CircleSharingService.swift` — `@MainActor` service exposing:
  ```swift
  func share(_ circle: Circle) async throws(CircleSharingError) -> CircleSharePayload
  func acceptShare(metadata: CKShare.Metadata) async throws(CircleSharingError)
  ```
  Internally it uses `CKContainer.default()`, creates the per-circle zone (`CKRecordZone(zoneName: circle.id.uuidString)`) idempotently, creates a `CKRecord` mirror for the Circle, builds a `CKShare` with `publicPermission = .none`, saves the share, and returns the `CKShare.url`. Acceptance hands off to `CKAcceptSharesOperation`.
- `Services/CloudKit/CircleSharePayload.swift` — Value type wrapping `share: CKShare`, `container: CKContainer`, `url: URL`, `participantRoleHint: MemberRole`.
- `Services/CloudKit/CircleSharingError.swift` — `enum CircleSharingError: LocalizedError, Sendable { case notSignedIntoiCloud, capReached, ckFailure(String), invalidShareMetadata }`.

### App / scene
- `App/AppDelegate.swift` — `final class AppDelegate: NSObject, UIApplicationDelegate` that returns a `UISceneConfiguration` bound to our `CircleSceneDelegate`.
- `App/CircleSceneDelegate.swift` — `final class CircleSceneDelegate: UIResponder, UIWindowSceneDelegate` whose only job is `windowScene(_:userDidAcceptCloudKitShareWith:)` → forward to `CircleSharingService.shared.acceptShare(metadata:)`. Acceptance is published via `NotificationCenter`/`AsyncStream` so SwiftUI views can react.

### Features/Members
- `Features/Members/MembersListView.swift` — Section list keyed by `MemberStatus` (Active / Invited / Removed). Each row shows display name, role badge, joined/invited timestamp. Owner sees an `Invite member` toolbar button (disabled when `activeCount >= memberCap`).
- `Features/Members/AddMemberView.swift` — Sheet with display-name field, role picker (excludes `.owner` and `.careRecipient` for v1 to keep flows narrow), "Send invite" button. Validates 8-member cap. On confirm: writes a `Member(status: .invited)` row locally and calls `CircleSharingService.share(circle:)`, then presents `ActivityShareSheet` with the share URL.
- `Features/Members/MemberRoleBadge.swift` — Reusable view turning a `MemberRole` into a sage-tinted capsule label.
- `Features/Members/MemberStatusBadge.swift` — Same for `MemberStatus`.
- `Features/Members/ActivityShareSheet.swift` — `UIViewControllerRepresentable` wrapping `UIActivityViewController([URL, String])`.

### DesignSystem
- `DesignSystem/SectionHeader.swift` — Spec-consistent uppercase footnote header used by Members list and future list-style screens.

### Docs
- `docs/cloudkit_testing.md` — Runbook for testing CloudKit on real devices.

## Files to modify

- `App/CareCircleApp.swift` — Switch `ModelConfiguration` to use `.private("iCloud.Res.CareCircle")`. Add `@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate`.
- `Models/Circle.swift` — Drop `@Attribute(.unique)` from `id`. Provide defaults: `name = ""`, `ownerAppleUserID = ""`. Init unchanged.
- `Models/CareRecipient.swift` — Drop `@Attribute(.unique)`. Provide default for `firstName = ""`. Init unchanged.
- `Models/Member.swift` — Drop `@Attribute(.unique)`. Provide defaults for `appleUserID`, `displayName`, `roleRaw`. Add new fields: `statusRaw: String = MemberStatus.active.rawValue`, `invitedAt: Date?`, `invitedByAppleUserID: String?`, `acceptedAt: Date?`, `inviteShareURLString: String?`. Computed `status: MemberStatus` accessor mirroring the `role` pattern (log + default to `.removed` on unknown raw).
- `Features/Circle/CreateCircleView.swift` — When creating the owner Member, set `status: .active` and `invitedByAppleUserID: nil` (no migration needed; defaults cover existing rows).
- `Features/Circle/CircleDetailView.swift` — Replace inline "Members" preview with a `NavigationLink` into `MembersListView`.

## Files to delete

None.

## Data model changes

```swift
@Model
final class Circle {
    var id: UUID = UUID()                      // unique by app-level guarantee; CloudKit forbids @Attribute(.unique)
    var name: String = ""
    var ownerAppleUserID: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \CareRecipient.circle)
    var careRecipient: CareRecipient?

    @Relationship(deleteRule: .cascade, inverse: \Member.circle)
    var members: [Member] = []
}

@Model
final class CareRecipient {
    var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String?
    var dateOfBirth: Date?
    @Attribute(.externalStorage) var photoData: Data?
    var primaryConditions: [String] = []
    var createdAt: Date = Date.now
    var circle: Circle?
}

@Model
final class Member {
    var id: UUID = UUID()
    var appleUserID: String = ""
    var displayName: String = ""
    var roleRaw: String = MemberRole.viewOnly.rawValue
    var statusRaw: String = MemberStatus.active.rawValue
    var joinedAt: Date = Date.now
    var invitedAt: Date?
    var invitedByAppleUserID: String?
    var acceptedAt: Date?
    var inviteShareURLString: String?
    var circle: Circle?
}

enum MemberStatus: String, CaseIterable, Sendable, Codable {
    case active                 // joined + present
    case invited                // share issued, awaiting acceptance
    case removed                // owner revoked
}
```

All defaults match `NSPersistentCloudKitContainer`'s migration requirements: every non-optional property has a default expression so CloudKit can backfill records that arrive without that field.

## CloudKit zone + sharing topology

```
CKContainer( iCloud.Res.CareCircle )
├── privateCloudDatabase
│   ├── _defaultZone                       (SwiftData ModelContainer writes here under .private)
│   └── zone:circle-<UUID>                 (created by CircleSharingService on demand)
│       ├── CKRecord("Circle", recordID: in this zone)   ← mirror of SwiftData Circle
│       └── CKShare(rootRecord: Circle, publicPermission: .none)
│
└── sharedCloudDatabase
    └── zone:circle-<UUID>                 (visible to accepted participants)
```

The Circle mirror record carries only what's needed to identify the circle (`name`, `ownerAppleUserID`, `createdAt`). Participants populate full data via SwiftData's CloudKit sync once their `ModelContainer` reconciles the shared zone — this is the SwiftData behavior we get for free from `.private(...)` + CKShare acceptance.

Custom zones are mandatory for sharing (the default zone cannot host a CKShare). The zone name is the Circle UUID so that deleting a Circle later cleanly nukes its zone.

## Public API surface (Phase 3 additions)

```swift
struct CircleSharePayload: Sendable {
    let url: URL
    let share: CKShare
    let container: CKContainer
    let participantRoleHint: MemberRole
}

enum CircleSharingError: LocalizedError, Sendable {
    case notSignedIntoiCloud
    case capReached
    case ckFailure(String)
    case invalidShareMetadata
}

@MainActor
final class CircleSharingService {
    static let memberCap = 8
    static let shared = CircleSharingService()

    func share(_ circle: Circle, suggestedRole: MemberRole) async throws(CircleSharingError) -> CircleSharePayload
    func acceptShare(metadata: CKShare.Metadata) async throws(CircleSharingError)
    func iCloudAccountStatus() async -> CKAccountStatus
}
```

> **On singletons:** CLAUDE.md forbids singletons. `CircleSharingService.shared` is a single-cell escape hatch for the `UISceneDelegate` to call without dependency injection — UIKit owns the scene delegate's lifetime, so we cannot pass services through it. SwiftUI call sites still inject the service via `@Environment(\.circleSharingService)` for testability. The single instance is set at app launch by `CareCircleApp.init`.

## Permission model (placeholder for now)

Real role enforcement is a Phase 4+ concern (it bites once Activities, Meds, Documents have per-role rules). Phase 3 introduces the scaffold:

```swift
struct CirclePermissions {
    let role: MemberRole
    var canInviteMembers: Bool   { role == .owner }
    var canRemoveMembers: Bool   { role == .owner }
    var canEditCareRecipient: Bool { role == .owner || role == .paidFamily }
    var canViewMembers: Bool     { true }
}
```

`CirclePermissions(role:)` is consulted from `MembersListView` to decide whether to render the Invite button.

## Scene delegate flow

```
1. User taps share URL on invitee's device.
2. iOS posts windowScene(_:userDidAcceptCloudKitShareWith:).
3. CircleSceneDelegate calls CircleSharingService.shared.acceptShare(metadata:).
4. Service builds CKAcceptSharesOperation, configures completion handler, adds to CKContainer.default().
5. On success, posts Notification.Name.circleShareAccepted with the share record ID.
6. RootView observes via .onReceive(.publisher(for: .circleShareAccepted)) and refreshes the @Query.
7. SwiftData ingests the shared zone records in the background — when they land, @Query updates naturally.
```

The notification path keeps SwiftUI views ignorant of UIKit lifecycle. We do *not* attempt to attribute the share back to the original `Member(status: .invited)` row in v1 — that requires storing the share record name on the Member at issue time and looking it up on accept. We'll do that once we wire the activity feed in Phase 4 and have a place to surface "Sarah just joined." For Phase 3, acceptance simply yields a new Circle visible to the invitee.

## Test plan

Simulator (iPhone 16 Pro Max) — the only thing we can verify without two devices:

1. Cold launch on freshly wiped sim → Sign in with Apple → Home empty state.
2. Create a Circle ("Mom's Care", "Eleanor", DOB ~80yo, conditions "type 2 diabetes").
3. Tap More → Your Circle → Members → owner row visible as "You · Primary caregiver · Active".
4. Tap **Invite member** → AddMemberView appears. Try entering empty display name → Send disabled.
5. Enter "Daniel Park", role "Family member", tap Send. Expected on Simulator: a `CircleSharingError.notSignedIntoiCloud` toast (Simulator's iCloud account is usually not signed in for our test rig). The `Member(status: .invited)` row is NOT written if sharing fails (transactional rollback).
6. Force-quit + relaunch → state preserved.
7. Add 7 invited members (use the "force iCloud account" workaround documented in cloudkit_testing.md, or temporarily stub the service to no-op the CK call). The 8th add (which would be the 9th total member) shows "This Circle is full (8 members)" + Send disabled.

Real-device matrix (manual, see `docs/cloudkit_testing.md`):

1. Owner device: sign in as test iCloud user A. Create Circle. Invite → share via iMessage to user B.
2. Invitee device: sign in as test iCloud user B. Receive iMessage → tap link → CareCircle launches → share accepted → Circle appears in More → Your Circle.
3. Toggle the invitee offline, post a hypothetical mutation on the owner, come back online → see the change land within 30 seconds.

We will not write XCUITests in this phase (covered by hard rule #2 in CLAUDE.md).

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| SwiftData CloudKit container fails to migrate the existing Phase-2 store because `@Attribute(.unique)` is dropped | The Phase 2 data set is a single test Circle from manual QA. We accept a one-time data-loss risk on dev devices. Production has no users yet. If we need a safer path in real use, ship a Lightweight Migration plan added by setting `versionedSchema` in a follow-up phase. |
| `CircleSharingService.shared` smells like a singleton | Acknowledged in CLAUDE.md note above. The escape hatch is bounded — UIKit scene delegates simply cannot receive injected dependencies through `init`. SwiftUI views still use Environment injection. |
| Simulator yields `CKError.notAuthenticated` even with iCloud signed in | Document the precise iCloud-sign-in steps for the Simulator (Settings ▸ Sign in to your iPhone ▸ Apple ID); confirm in cloudkit_testing.md. If the Simulator still fails, fall back to a real device. |
| Custom zones might pile up if a user creates and deletes Circles repeatedly | Out of scope for v1. The deletion path becomes a Phase 12 polish task. |
| `UICloudSharingController` was deprecated in iOS 17 in favor of `ShareLink(item:preview:)` for `Transferable` types | We don't use `UICloudSharingController` — we hand the `CKShare.url` to the system share sheet via `UIActivityViewController`. Simpler, fewer surprises, works in iOS 26. |
| The `CircleSceneDelegate` adds UIKit lifecycle to an otherwise pure SwiftUI app | Required by CloudKit's share-acceptance API. The delegate has exactly one method body; we accept the surface-area cost. |

## Definition of Done

1. `xcodebuild` build succeeds for `iPhone 16 Pro Max` destination, zero new warnings.
2. SwiftData container initializes with `.private` CloudKit configuration without crashing on launch.
3. Sign-in → Create Circle → open Members → render owner-only members list with "Active" badge.
4. Invite flow: display-name + role picker + 8-member cap enforced + share sheet presents the CKShare URL on real devices (Simulator surfaces `notSignedIntoiCloud` gracefully).
5. Scene delegate compiles and forwards `userDidAcceptCloudKitShareWith` to the sharing service (verified by adding a `print` breakpoint — full acceptance verified on the real-device test rig later).
6. `docs/cloudkit_testing.md` exists and contains the real-device test runbook + Simulator workarounds.
7. SwiftFormat clean. SwiftLint clean.
8. Phase 3 commit follows Conventional Commits and pushes to `origin/main`.

## Self-critique

Three weakest decisions:

1. **`CircleSharingService.shared` is a controlled singleton.** UIKit's scene-delegate boundary forces this. Mitigated by limiting the singleton role to "the scene delegate's call-target"; SwiftUI views still inject via Environment.
2. **No persistent linkage from the invited `Member` row to the share record name.** Acceptance on the invitee's side will create a new owner-perspective Member only when the SwiftData CloudKit sync finishes propagating; the original `Member(status: .invited)` row sits as a UI-only ghost until Phase 4 wires the back-link. We document this and move on rather than carrying half-baked state.
3. **No revoke-share flow in this phase.** Owners can mark a Member `.removed` locally, but the corresponding CKShare participant removal is deferred. We surface a "(revoke pending)" badge so the UI is honest.

Two over/under-engineered:

- **Under-engineered:** No retry on transient CKErrors (e.g., `networkUnavailable`). Phase 3 surfaces the failure and lets the user retry manually. Background-retry deserves its own phase.
- **Maybe over-engineered:** Building a separate `CircleSharePayload` value type and `CircleSharingError` enum rather than throwing a generic `Error`. The payoff: typed-throws on `share(_:)` makes the call site exhaustive; the enum stays small (4 cases) so the maintenance cost is real but low.

One thing a future engineer might curse me for:

- The owner Member row's `inviteShareURLString` is `nil`. We don't store the share URL anywhere for owners. If the owner wants to re-send an invitation they have to issue a new share — there's no "show me last week's invite link." Acceptable for v1; revisit in Phase 12 polish.
