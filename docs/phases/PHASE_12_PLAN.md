# Phase 12 — Care Recipient simplified mode + accessibility polish + TestFlight prep

## End state
1. **Simplified Mode**: when the signed-in user is a Circle member with
   `role == .careRecipient`, the app boots into a stripped-down view
   designed for seniors: big type, fewer controls, one-tap call & text
   to the primary emergency contact, and a single-screen summary of
   today's medications and next appointment. A toggle in MoreView's
   Account section lets any member preview the mode regardless of
   role (for testing and for caregivers who hand the phone to the
   recipient).
2. **Accessibility polish**: every feature has VoiceOver labels on
   interactive elements, every tap target is ≥ 44×44 pt, Dynamic Type
   scales without text truncation up through the AX accessibility
   sizes, and Reduce Motion is honored on the SOS countdown and
   activity feed.
3. **TestFlight prep**: `docs/TESTFLIGHT_PREP.md` enumerates the
   pre-flight checklist — deployment target review (currently iOS
   26.4 in the Xcode project vs iOS 17+ in the spec), App Privacy
   answers, screenshots required, archive + upload workflow, and the
   Critical Alert entitlement application status.

## Out-of-scope for this phase
- **A dedicated "kiosk mode" Guided Access integration.** iOS's
  Guided Access works on top of the app; we don't need our own
  lock-down. A future polish task can hint the user to enable it.
- **Voice-over scripting of every flow.** Apple Accessibility
  Inspector + manual VoiceOver pass per screen is sufficient.
  Automated XCUITest accessibility audits are deferred until after
  TestFlight launches.
- **Magnified launch screen.** The launch image already uses SF
  Symbols + system font sizing, which scales correctly with system
  text size on iOS 17+.
- **TestFlight build upload.** We document the workflow but do not
  perform an actual upload — that requires a paid Apple Developer
  account login and is the user's first physical-device step.

## Build sequence

1. **`SimplifiedModePreference.swift`** — a tiny `@Observable`
   wrapper around `UserDefaults` storing the manual override
   (`isManualOverrideEnabled`). Provides `effectiveIsActive(for:)`
   that ORs the manual override with `viewerRole == .careRecipient`.
   Injected via SwiftUI `Environment`.
2. **`SimplifiedHomeView.swift`** — single-screen view shown in
   place of `MainTabView` when simplified mode is active. Layout:
   - Top: large recipient/caregiver greeting ("Good morning,
     Eleanor"). 36 pt rounded display.
   - "Call family" + "Text family" big buttons (88 pt height, 36 pt
     label text). Wire to primary `EmergencyContact` via `tel://`
     and `sms://` (mirrors the SOSDetailView pattern).
   - "Today's medicine" card: count of doses, taken vs remaining,
     time of next dose. Tapping opens MedsView for full detail.
   - "Next appointment" card: title + date/time + provider. Empty
     state if none in the next 7 days.
   - "Exit simplified mode" footer button — only visible when
     manual override is on; gone when role-based.
3. **`SimplifiedModeToggleRow.swift`** — settings row in MoreView's
   Account section: toggle for `isManualOverrideEnabled`. Footer
   text explains "Designed for the person being cared for. Big
   buttons, fewer screens, one-tap call to family."
4. **RootView integration** — after authState resolves to signedIn,
   compute `effectiveSimplifiedMode`. If true, present
   `SimplifiedHomeView`; else `MainTabView`. The `Member` for the
   active Circle is looked up via the existing query pattern
   (`circles.first.members.first(where: appleUserID == user.id)`).
5. **Accessibility audit pass** — concrete edits across the
   codebase:
   - HomeView: ensure SOS button has explicit `accessibilityLabel`
     ("Emergency SOS, double-tap and hold to start countdown").
   - ActivityFeed cells: combine reactions/comments into a single
     accessible element with a usage hint.
   - MedicationRowView: announce dose name + dosage + next scheduled
     time as a single phrase.
   - SOSCountdownView: respect Reduce Motion by disabling the
     animated stroke trim; keep the numeric countdown.
   - ActivityFeedView and TodayTimelineView: tap targets that
     wrap an icon-only button get `.frame(minWidth: 44, minHeight: 44)`.
   - Color contrast: spot-check ccSecondary on ccBackground (current
     ratio is ~4.6:1) and ccSecondary on ccSurface (~3.8:1 — needs
     bump). Adjust ccSecondary toward ccText by ~10% to hit 4.5:1.
   - Tab bar: each Label already provides system VoiceOver text;
     no change needed.
6. **`docs/TESTFLIGHT_PREP.md`** — markdown checklist covering:
   - Deployment target review.
   - Required device permissions and rationale strings in Info.plist
     (camera, mic, speech recognition, contacts, calendar, photo
     library, location-when-in-use, notifications).
   - App Privacy questionnaire data categories: health, contacts,
     photos, audio data, identifiers, diagnostics.
   - Screenshot list (iPhone 6.7", iPhone 6.1", iPad 12.9" required
     by App Store).
   - Archive + upload workflow via Xcode.
   - Critical Alert entitlement status (still pending at time of
     phase).
   - Pre-TestFlight smoke test checklist (12 items, mirroring the
     spec §10 acceptance tests for v1.0).
7. swiftformat + swiftlint clean.
8. xcodebuild green.
9. Commit + push.

## Risks / things to watch
- **Color tweak risk.** Bumping `ccSecondary` darker could affect
  the look of every screen. Keep the change minimal (~5–10% L*
  shift) and eyeball the major surfaces.
- **Member lookup at root.** RootView currently doesn't load
  Circles. We can move that query down into a wrapper view that
  takes the signedInUser and produces either a SimplifiedHomeView
  or MainTabView; that keeps the SwiftData query out of RootView's
  status-switching code path. Implementation: introduce
  `SignedInRootView` between RootView and MainTabView/SimplifiedHomeView.
- **Reduce Motion detection.** Use `@Environment(\.accessibilityReduceMotion)`.
  When true, animate `progress` with `.animation(nil, value: progress)`
  on the trim stroke. The numeric countdown text still updates because
  the state change is not animated.
- **MoreView is not visible in simplified mode**, so the manual-override
  toggle is unreachable once enabled unless the user toggles it back
  via the SimplifiedHomeView footer button. The footer "Exit
  simplified mode" button must always be visible when the mode was
  manually enabled; for role-based activation it stays off the screen
  (as designed).

## Safety rules (carry-forward)
- No marketing language for accessibility ("blazingly accessible").
  Describe behaviors, not adjectives.
- Don't claim the simplified mode is a medical-device interface or
  fall-detection system.
- Never hide the SOS path — even in simplified mode, the "Call
  family" button doubles as the primary safety control. Document
  this explicitly so reviewers don't think the SOS feature is gone.

## Future TODOs left as comments in code
- `SimplifiedModePreference`: CloudKit-sync the preference so the
  recipient's setting carries across their devices. Requires
  `NSUbiquitousKeyValueStore` wiring.
- `SimplifiedHomeView`: surface SOS as a discrete button (currently
  collapsed into the primary "Call family" CTA). Awaiting product
  feedback before adding a second emergency control.
- `SimplifiedHomeView`: add a tutorial overlay the first time the
  mode activates, explaining the buttons.
