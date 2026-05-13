# CareCircle — TestFlight Prep Checklist

This is the pre-flight checklist for shipping the first internal
TestFlight build of CareCircle v1. It is intentionally a runbook,
not a tutorial — each section assumes the reader knows how Apple
Developer / App Store Connect / Xcode 26 work, and only documents
the *specific* things this app needs.

Last updated: 2026-05-13. Status: ready for the user's first physical
device + Apple ID login. None of these steps require Claude Code.

---

## 1. Deployment target review

**Current state:** The Xcode project ships with
`IPHONEOS_DEPLOYMENT_TARGET = 26.4`, which limits installs to iOS
26.4+ devices. The product spec calls for "iOS 17+" as the official
floor.

**Decision required before submission:**
- **Option A — stay on 26.4.** Required if you want to keep the
  Foundation Models on-device entity extraction (Phase 6) and the
  newest SwiftUI APIs without back-porting. Cuts the addressable
  device list to iPhones from the iPhone 16 line forward.
- **Option B — drop to iOS 17.** Re-enables installs on iPhone XS
  and later, but the Phase 6 entity extractor must fall back to a
  cloud-proxy path (PHI-stripped). Several iOS 26-only SwiftUI APIs
  (e.g. `@Bindable` ergonomics, `Toolbar` defaults) need API checks
  or `if #available` guards.

Recommended for v1 TestFlight: **stay on iOS 26.4** for the initial
internal build, gather feedback from family beta testers on iPhone
16-class hardware, then make the back-port decision when sizing
production launch.

How to change: Xcode → project navigator → CareCircle target →
General → Minimum Deployments. There is no equivalent flag in the
entitlements file — it lives only in build settings.

---

## 2. Required device permissions and rationale strings

`Info.plist` already declares the following keys with caregiver-
appropriate strings (verified 2026-05-13 against
`CareCircle/Info.plist`):

| Key | Used by | Status |
|---|---|---|
| `NSCalendarsFullAccessUsageDescription` | Appointment mirror (Phase 8) | ✅ |
| `NSCameraUsageDescription` | Medication label scanner (Phase 7) | ✅ |
| `NSLocationWhenInUseUsageDescription` | SOS location capture (Phase 10) | ✅ |
| `NSMicrophoneUsageDescription` | Voice handoff (Phase 5) | ✅ |
| `NSSpeechRecognitionUsageDescription` | On-device transcription (Phase 5) | ✅ |

**Still to add before TestFlight if those flows are reachable:**
- `NSPhotoLibraryUsageDescription` — needed if you allow attaching
  saved photos (vs camera-only) to activity posts. Confirm by
  testing the photo composer; if PHPicker is used, no string is
  required.
- `NSContactsUsageDescription` — only needed if you import phone
  contacts for emergency-contact setup. Current flow is manual
  entry, so this can stay omitted.

UIBackgroundModes already includes `remote-notification` for the
push pipeline.

---

## 3. Entitlements status

| Capability | Status | Notes |
|---|---|---|
| Sign in with Apple | ✅ enabled | `com.apple.developer.applesignin = ["Default"]` |
| CloudKit (private + shared) | ✅ enabled | container `iCloud.Res.CareCircle` |
| Push (APNs) | ✅ development | `aps-environment = development`. **Flip to `production` before App Store review.** |
| Critical Alerts | ⏳ **pending Apple approval** | Required for SOS + missed-critical-meds escalation per spec §5.5. Submit the form at https://developer.apple.com/contact/request/critical-alerts — be precise about the medical-coordination use case. The app must continue to work if the request is denied; the fall-back is time-sensitive notifications. |

---

## 4. App Privacy questionnaire (App Store Connect → App Privacy)

The questionnaire wants per-data-category answers. Here is what
CareCircle collects in v1 (CloudKit-only path):

| Category | Collected? | Linked to user? | Used for tracking? | Notes |
|---|---|---|---|---|
| Health & Fitness — Health | Yes | Yes | No | Medications, doses, conditions, vitals — stored in CloudKit private/shared. |
| Contact Info — Name | Yes | Yes | No | From Sign in with Apple. |
| Contact Info — Email | Yes (optional) | Yes | No | From SiwA. Often Apple's private relay. |
| Contact Info — Phone | Yes | Yes | No | Emergency contacts, entered manually by the user. |
| User Content — Photos or videos | Yes | Yes | No | Activity attachments; documents (E2EE-encrypted blob in CloudKit). |
| User Content — Audio | Yes | Yes | No | Voice handoff notes (raw audio + on-device transcript). |
| User Content — Other content | Yes | Yes | No | Activity text bodies, appointment notes, etc. |
| Identifiers — User ID | Yes | Yes | No | Apple ID `sub` used as primary key. |
| Usage Data — Product Interaction | No | — | — | We do not ship analytics in v1. |
| Diagnostics — Crash / performance | No | — | — | No third-party SDK; Apple's standard crash logs only (opt-in by user). |
| Location — Coarse | Yes (event-scoped) | Yes | No | SOS captures lat/lng at trigger time only. |

"Used for tracking" answers should all be **No** — we do not share
identifiers with third parties.

---

## 5. Required screenshots

The App Store requires at minimum these device classes (Apple
updated requirements 2024). For each, capture six screens
illustrating the canonical flows:

1. Home (with Activity feed populated)
2. Today (timeline with appointments + meds)
3. Medication detail with schedule + scan source
4. Voice handoff composer mid-recording
5. SOS countdown (full-screen red surface)
6. Care minutes export PDF preview

| Class | Resolution | Notes |
|---|---|---|
| iPhone 6.7" / 6.9" display | 1290 × 2796 | iPhone 16 Pro Max canonical |
| iPhone 6.1" display | 1179 × 2556 | iPhone 16 / 15 / 14 |
| iPad 12.9" (3rd gen+) | 2048 × 2732 | Required if listed for iPad. We are **iPhone-only** in v1; skip. |

Use Simulator → File → Save Screen + the iPhone 16 Pro Max sim
running a populated seed circle. Color-correct the seed data so
real PHI is never on the screenshots.

---

## 6. Archive + upload workflow

Step-by-step, run by the user (Claude Code cannot perform these):

1. Bump `MARKETING_VERSION` (currently 1.0) only if shipping a new
   user-visible version. For TestFlight builds within the same
   version, only `CURRENT_PROJECT_VERSION` needs to increment.
2. Xcode → top bar → device dropdown → **Any iOS Device (arm64)**.
3. Product → Archive. This takes several minutes; SwiftData macro
   expansion plus the CloudKit container linkage dominate.
4. When the Organizer opens, select the new archive → **Distribute
   App** → **App Store Connect** → **Upload**.
5. Pick the automatically managed signing profile (Apple Developer
   team `487LC4H9U4`).
6. Wait for the App Store Connect "Processing" email — usually
   under 15 minutes.
7. In App Store Connect → TestFlight → Builds → click the new
   build, fill in **Test Information** (what's new in this build,
   beta app description, beta app feedback email).
8. Add internal testers (your own Apple ID first; then up to 100
   from the same Apple Developer team).
9. For external testers (up to 10,000), submit for Beta App
   Review. Allow 24–48 hours.

---

## 7. Pre-TestFlight smoke test (12 items)

Run these on a physical iPhone 16 Pro before uploading.

1. Cold launch with no signed-in user → SignInView shows; Sign
   in with Apple completes; lands on Home.
2. Create a Circle from the empty state. Card appears in Home.
3. Add a Care Recipient with name + DOB. Persists across relaunch.
4. Invite a second member via CKShare. Accept on a second device
   logged into a different iCloud account.
5. Post a text activity from device A; verify it appears on
   device B within ~5 seconds.
6. Record a voice handoff note ≤ 30s; transcript appears,
   on-device entity extraction surfaces a chip.
7. Add a medication via the label scanner; verify the openFDA
   side panel populates within 5s on Wi-Fi.
8. Mark a dose taken; verify the activity feed shows the system
   "Dose taken" entry on the other device.
9. Create an appointment; verify it mirrors into the iOS
   Calendar app (Calendar permission grant on first attempt).
10. Trigger SOS; verify the 30-second countdown runs and the
    primary contact is dialed via `tel://`.
11. Toggle "Simplified mode" in More → Accessibility; verify the
    app switches to SimplifiedHomeView and "Exit simplified mode"
    appears at the bottom.
12. With VoiceOver on, traverse every tab and confirm every
    interactive element announces a meaningful label.

---

## 8. Known issues / open items

- The app is iOS 26.4-only in v1; the spec asks for iOS 17. See §1.
- Critical Alert entitlement is pending Apple approval. Until
  granted, SOS notifications respect Focus / Do Not Disturb.
- CloudKit-shared circles cannot be tested on Simulator without
  signing into iCloud — use physical devices.
- Care minutes PDF export does not include caregiver e-signatures
  in v1; users sign the printed PDF by hand. Tracked as a Phase 13+
  TODO.
- HealthKit reads return empty on Simulator — test vitals flows on
  device with seeded HealthKit data.

---

## 9. Not in v1 scope (so don't trip on these)

- Apple Watch companion app
- iPad-specific layout (we do not list iPad)
- macOS Catalyst build
- Family Sharing-based plan billing
- Stripe / RevenueCat payment integration
- B2B HIPAA-bearing flow (Railway backend, BAA, audit-log API)
- Multi-region / multi-language at first launch (English-only)

---

## 10. After first TestFlight upload

1. Mark the first internal build as "complete" in Linear or your
   tracker.
2. Forward the TestFlight invite URL to family beta testers (≤ 5
   for the first wave).
3. Capture feedback in a single shared note for one week before
   making any post-feedback changes — avoid thrashing the build.
4. Schedule the iOS 17 back-port decision review for two weeks
   after first upload.
