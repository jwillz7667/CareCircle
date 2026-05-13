# Phase 2 — Circle creation + Care Recipient profile

## Goal

Signed-in user creates a Circle (name + Care Recipient: first name, last name, DOB, photo, primary conditions), data persists across launches via SwiftData, and the Circle appears on the More tab with an edit affordance. Home tab adapts: empty until a Circle exists, hero-style summary once it does. CloudKit is still configured-only — Phase 3 wires syncing.

## Files to create

Under `CareCircle/Sources/`.

### Models
- `Models/Circle.swift` — `@Model final class Circle` with `id`, `createdAt`, `name`, `ownerAppleUserID`, optional `careRecipient`, and `members` (`[Member]`). Relationships use `.cascade` delete rules so removing a Circle purges its dependents.
- `Models/CareRecipient.swift` — `@Model final class CareRecipient` with `id`, `firstName`, optional `lastName`, optional `dateOfBirth`, optional `photoData` (`@Attribute(.externalStorage)`), `primaryConditions: [String]`, inverse `circle` relationship.
- `Models/Member.swift` — `@Model final class Member` representing one person in a Circle. Phase 2 only ever creates the `.owner` Member; Phase 3 adds the rest.
- `Models/MemberRole.swift` — `enum MemberRole: String, Codable, CaseIterable, Sendable` covering `owner / familyMember / paidAide / paidFamily / careRecipient / viewOnly` per spec §2.3.

### Features/Circle
- `Features/Circle/CareRecipientDraft.swift` — `struct CareRecipientDraft: Equatable` (firstName, lastName, dateOfBirth, conditions, photoData) backing the form, with a `validate()` returning typed errors and a `commit(to: CareRecipient)` helper for edit-mode round-trips.
- `Features/Circle/CareRecipientFormFields.swift` — Reusable `View` rendering the form rows (text fields, optional DOB toggle + picker, photo picker, conditions chips). No save logic; binds to the draft.
- `Features/Circle/CreateCircleView.swift` — Sheet flow: Circle name + Care Recipient details → save → dismiss. Reads `AuthState` for `ownerAppleUserID`, owner's `displayName`. Creates `Circle`, `CareRecipient`, and one `.owner` `Member` in a single `ModelContext.transaction`.
- `Features/Circle/EditCareRecipientView.swift` — Sheet that edits an existing Care Recipient via the same form fields.
- `Features/Circle/CircleDetailView.swift` — Shown from the More tab. Header with photo + name + DOB age + conditions chips, plus a "Members (1)" row that previews the owner and an "Edit Care Recipient" button.
- `Features/Circle/CircleHero.swift` — Reusable header used on Home for "current Circle" state (avatar + name + tap to view detail).

### DesignSystem additions
- `DesignSystem/PrimaryButtonStyle.swift` — `ButtonStyle` matching the spec's sage palette, 44pt minimum tap target, Dynamic Type aware.
- `DesignSystem/PhotoCircleView.swift` — Circular avatar that renders a `Data?` blob or a `person.crop.circle.fill` SF Symbol fallback, with an optional `PhotosPicker` overlay for edit mode.
- `DesignSystem/FormRow.swift` — Sage-tinted, label-above-input row for consistent spacing inside `Form`s.

## Files to modify

- `App/CareCircleApp.swift` — Update `Schema` to `[Circle.self, CareRecipient.self, Member.self]`. Drop `AppMetadata` from the schema.
- `Features/Home/HomeView.swift` — Query the active Circle (owned by the signed-in user). Empty: friendly hero + "Create your Circle" button presenting `CreateCircleView`. Present: render `CircleHero` + "No recent activity" placeholder.
- `Features/More/MoreView.swift` — Add a "Your Circle" section with `NavigationLink` to `CircleDetailView` when a circle exists; show a stub row when not.

## Files to delete

- `Models/AppMetadata.swift` — Replaced by the real models. Promised in Phase 1 plan §self-critique #2.

## Data model changes

```swift
@Model
final class Circle {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerAppleUserID: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CareRecipient.circle)
    var careRecipient: CareRecipient?

    @Relationship(deleteRule: .cascade, inverse: \Member.circle)
    var members: [Member]
}

@Model
final class CareRecipient {
    @Attribute(.unique) var id: UUID
    var firstName: String
    var lastName: String?
    var dateOfBirth: Date?
    @Attribute(.externalStorage) var photoData: Data?
    var primaryConditions: [String]
    var createdAt: Date
    var circle: Circle?
}

@Model
final class Member {
    @Attribute(.unique) var id: UUID
    var appleUserID: String
    var displayName: String
    var roleRaw: String           // stored as String to keep CloudKit-friendly
    var joinedAt: Date
    var circle: Circle?

    var role: MemberRole { get / set via raw value }
}
```

All relationships optional, all properties have defaults — this keeps the door open for Phase 3's CloudKit migration without a schema break.

## Public API surface

Internal access on every new type; nothing escapes the app target. Notable initializers:

```swift
init(name: String, ownerAppleUserID: String)                          // Circle
init(firstName: String, lastName: String? = nil, dateOfBirth: Date? = nil,
     photoData: Data? = nil, primaryConditions: [String] = [])        // CareRecipient
init(appleUserID: String, displayName: String, role: MemberRole)      // Member
```

`CareRecipientDraft` exposes:

```swift
struct CareRecipientDraft: Equatable {
    var firstName: String = ""
    var lastName: String = ""
    var dateOfBirth: Date?
    var photoData: Data?
    var primaryConditionsInput: String = ""
    var primaryConditions: [String] { … parsed from comma-separated input … }
    var validationError: CareRecipientValidationError? { … }
}

enum CareRecipientValidationError: LocalizedError {
    case firstNameRequired
    case firstNameTooLong
    case dobInFuture
}
```

## Test plan

Still no automated test target. Manual verification on iPhone 16 Pro Max simulator:

1. Fresh install → Sign in with Apple → land on Home with **Create your Circle** CTA.
2. Tap CTA → `CreateCircleView` sheet appears.
3. Enter Circle name = "Mom's Care", first name = "Eleanor", last name = "Park", DOB = an 80-year-old date, conditions = "type 2 diabetes, hypertension". Photo picker shows the placeholder.
4. Tap **Save** → sheet dismisses → Home now shows the hero ("Eleanor Park", placeholder avatar).
5. Switch to **More** → "Your Circle" row shows "Mom's Care · Eleanor Park" → tap → `CircleDetailView` opens.
6. Tap **Edit Care Recipient** → change first name to "Ellie" → save → header updates.
7. Cold-restart simulator → app lands on Home with Eleanor's hero already populated (SwiftData restore).
8. Validation: clear first name → Save disabled; set DOB to 2030 → form shows "DOB cannot be in the future."
9. VoiceOver pass on `CreateCircleView`: each field has a label + value, photo picker reads "Care Recipient photo, button".

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Multiple Circles per user in v1 ambiguous in spec | Phase 2 derives "active circle" as `first` matching `ownerAppleUserID`. Multi-circle switcher is a Phase 3+ concern. |
| SwiftData migration when Phase 3 enables CloudKit on the same container | All fields default or optional, no DenyDelete rules — exactly what `NSPersistentCloudKitContainer` requires. Drops the placeholder `AppMetadata` cleanly: no real user data to migrate. |
| Photo blob bloats the store | `@Attribute(.externalStorage)` on `photoData` keeps the SQLite store small. |
| Care Recipient name re-keyed → app may persist `nil` when Apple omits credential names on subsequent sign-ins | Already covered by `AuthState.makeUser`; Phase 2 derives the owner's displayName from whatever the auth state currently exposes. |
| Member role enum string drift | `MemberRole` is `String`-backed with all cases declared; unrecognized raw strings decode as `.viewOnly` (least-privilege default) and emit an `AppLogger.persistence.error` so the issue is observable. |

## Definition of Done

1. `xcodebuild` build is green on iPhone 16 Pro Max sim, zero warnings introduced.
2. SwiftData container initializes with `Circle / CareRecipient / Member`, `AppMetadata` model file removed.
3. Home tab transitions from empty CTA to circle hero after creation, and back to empty if the circle is deleted.
4. More tab links to `CircleDetailView`, which shows the care recipient summary and offers edit.
5. Edit Care Recipient persists across an app relaunch.
6. Form-level validation prevents saving an empty first name or a future DOB.
7. SwiftLint clean across new files; SwiftFormat reports zero diffs.
8. Phase 2 commit follows Conventional Commits and is pushed to `origin/main`.

## Self-critique

Three weakest decisions reviewed against the quality bar:

1. **Storing `roleRaw: String` on `Member` instead of the enum directly** trades a tiny bit of ergonomic safety for the certainty that CloudKit-backed SwiftData (Phase 3) will accept the schema without surprises. The computed `role` accessor masks the cost. If by Phase 3 Apple confirms enum support is stable, swap the storage in one place.
2. **`primaryConditions` as `[String]`** is the spec's simplification. The real product probably wants ICD-10 codes or a SNOMED-CT picker; that lands in a future phase. For Phase 2 we accept the lightweight free-text list because the form is bound by what the caregiver remembers, not by a coding scheme.
3. **No CircleStore abstraction.** `@Query` + raw `ModelContext` keeps the call sites SwiftUI-idiomatic. The risk: if Phase 3's CKShare flow has to coordinate UI state with sync state, an `@Observable` controller will be more natural. Acceptable — the refactor cost is localized to two or three views.

Two over/under-engineered:

- **Under-engineered:** No undo for an accidental `Edit Care Recipient` save. SwiftData's `UndoManager` integration is one line on `ModelContainer`, but Phase 2 doesn't wire it. Phase 4 (feed posts) will need undo; we'll enable it then.
- **Maybe over-engineered:** A standalone `CareRecipientDraft` value type for the form, separate from the SwiftData `@Model`. The reason: SwiftData `@Model` instances are reference types tied to a `ModelContext`, which gets messy if the user opens the form, edits, and cancels. A draft value lets us avoid persisting partial edits. Worth the ~30 lines.

One thing a future engineer might curse me for:

- The "active Circle = first owned" rule lives inline in `HomeView` and `MoreView` instead of in a single helper. If we add a third query site (and we will, in Phase 4), promote it to `Circle.activeCircle(ownedBy:in:)` then.

## Outcome

Phase 2 shipped end-to-end:

- `Models/Circle.swift`, `Models/CareRecipient.swift`, `Models/Member.swift`, `Models/MemberRole.swift` created. `Models/AppMetadata.swift` deleted.
- `Features/Circle/CareRecipientDraft.swift` + `CareRecipientFormFields.swift` + `CreateCircleView.swift` + `EditCareRecipientView.swift` + `CircleDetailView.swift` + `CircleHero.swift` created.
- `DesignSystem/PrimaryButtonStyle.swift`, `PhotoCircleView.swift`, `FormRow.swift` added.
- `App/CareCircleApp.swift` schema migrated to `[Circle, CareRecipient, Member]`.
- `Features/Home/HomeView.swift` and `Features/More/MoreView.swift` query the active Circle; Home renders empty CTA or `CircleHero`; More links to `CircleDetailView`.
- `MainTabView.swift` passes `authState` into `HomeView`.

Verification:
- `xcodebuild -scheme CareCircle -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build` → `** BUILD SUCCEEDED **`, zero warnings.
- `swiftformat .` → 8 files reformatted, none flagged.
- `swiftlint --quiet` → no violations (only config notice about `unused_import` analyzer placement).

Deviations from plan:
- The DOB UX is "Add date of birth" toggle that reveals a `DatePicker` on, with `in: ...Date.now` to constrain to past dates (so `dobInFuture` validation only matters defensively). The plan implied an always-present picker.
- `validationSection` shows everything *except* `firstNameRequired` — the disabled Save button already signals that requirement; showing "First name is required" before the user has typed felt nag-y. `firstNameTooLong` and `dobInFuture` still surface.

Gotchas captured into CLAUDE.md:
- swiftformat `--self remove` vs `Logger` autoclosure interpolation — bind to a local before logging.
- `SwiftData.Circle` vs `SwiftUI.Circle` shadowing — Swift's local-type-first lookup keeps xcodebuild green, but SourceKit shows phantom errors until reindex.
