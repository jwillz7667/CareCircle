# Critical Alerts Entitlement — Application Packet

The `com.apple.developer.usernotifications.critical-alerts` entitlement is required for two CareCircle flows:

1. **SOS escalation** (Phase 10) — when a Care Recipient triggers SOS and the 30-second cancel window lapses, the app must alert the Primary Caregiver and emergency contacts even when their devices are in Silent / Do Not Disturb / Focus modes.
2. **Missed critical medication escalation** (Phase 7) — when a medication marked "critical" is missed past its grace window, all Circle members must be alerted regardless of device silence settings.

Apple grants Critical Alerts case by case. Approval typically takes 2–8 weeks. **File this early.**

---

## How to apply

1. Go to <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/>
2. Sign in as the Apple Developer account holder for team **`487LC4H9U4`**.
3. Fill in the form fields below verbatim.
4. Submit. Save the confirmation email — Apple replies to it with approval / questions / denial.

---

## Form answers (copy/paste ready)

### App Name
CareCircle

### App ID / Bundle Identifier
`Res.CareCircle`

### Team ID
`487LC4H9U4`

### App Store URL (if available)
*Not yet on the App Store — pre-launch. The app is in active development; we are filing for Critical Alerts ahead of TestFlight because Apple review for this entitlement takes 2–8 weeks and the entitlement is needed before our first public testing build. Happy to provide a TestFlight build for Apple review once we have an internal build ready.*

### What is the primary purpose of your app?

CareCircle is a family-caregiving coordination app for the Sandwich Generation: adult children juggling jobs and small kids while remotely or locally caring for an aging parent. The app coordinates medications, appointments, voice handoff notes, paid-aide shifts, encrypted documents (advance directives, insurance cards), and an emergency SOS path among the small group of family and paid caregivers around a single Care Recipient.

### Why does your app require Critical Alerts?

Two time-sensitive, life-safety scenarios:

**1. Emergency SOS escalation.** A Care Recipient (typically a senior with cognitive impairment, fall risk, or chronic conditions) can trigger an in-app SOS with a single tap. After a 30-second cancel window — designed to absorb accidental triggers — the app fans out an alert to the Primary Caregiver and a configured list of family / medical emergency contacts. These alerts MUST break through Silent Mode, Do Not Disturb, and Focus modes. A caregiver whose phone is on the nightstand at 3 AM with Focus enabled is the exact scenario this entitlement exists for. A missed SOS notification is a worst-case outcome — the senior is alone, the family member doesn't know, and minutes matter.

**2. Missed critical medication escalation.** Caregivers mark specific medications as "critical" — typically anti-seizure drugs, insulin, anti-rejection meds for transplant recipients, anticoagulants, or Parkinson's medications where a missed dose can trigger an acute medical event within hours. If a critical dose passes its grace window without being marked taken, CareCircle escalates a notification to every Circle member. These users have explicitly opted into critical-medication tracking knowing escalations may interrupt sleep or DND — that is the point of marking a med critical.

### What user controls will you provide?

- Critical Alerts are off by default on every install.
- During onboarding (and again whenever a user adds the first emergency contact or marks the first critical medication), the app presents a dedicated explainer screen and prompts via the standard `UNUserNotificationCenter` `criticalAlert` authorization. The user must explicitly grant; Apple's system prompt itself describes the override behavior.
- Granular toggles in Settings → Notifications:
  - "Critical Alerts for SOS" — on/off per Circle
  - "Critical Alerts for missed critical medications" — on/off per Circle
- A "Test Critical Alert" button in Settings lets the user verify the experience.
- Volume of Critical Alert sound is independently configurable (per Apple's HIG).
- Users can revoke critical-alert authorization at any time from iOS Settings → Notifications → CareCircle; the app detects this and surfaces a banner explaining that SOS and missed-critical-med alerts will fall back to time-sensitive notifications.

### What is the expected frequency of Critical Alerts?

Extremely low. Per Circle, in steady state, Critical Alerts fire when:
- A real SOS is triggered (rare; typically <1 per Circle per year — emergencies are rare events).
- A critical medication is genuinely missed past grace (rare for engaged caregivers; in pilot use we expect <1 per Circle per month).

We expect Critical Alert volume of roughly 1–2 alerts per user per quarter on average, with most users receiving zero in any given month. The app's notification design prefers time-sensitive over critical for non-life-safety events specifically so that Critical Alerts retain signal.

### Fallback if denied

If a user denies the Critical Alerts authorization, or if Apple denies our entitlement application, the app falls back to **time-sensitive notifications** for the same triggers. The user experience degrades gracefully: time-sensitive notifications still break through Focus Modes on supported iOS versions but respect Silent Mode and full Do Not Disturb. The SOS and missed-critical-med flows otherwise function identically. We never block app functionality on the entitlement.

### Privacy and PHI handling

CareCircle stores Protected Health Information including medication regimens, conditions, and appointment details. All PHI is encrypted at rest (pgcrypto on the backend, CryptoKit AES-256-GCM for sensitive documents end-to-end). The notification payload for Critical Alerts contains only a generic title ("CareCircle: urgent — [first name] needs attention") and a deep link; the body is intentionally PHI-free so that lock-screen exposure is minimized.

### Demo build / TestFlight access

Available on request once we cut our first build. We are pre-TestFlight and pre-App-Store; this entitlement application is being filed ahead of any submission specifically because of Apple's review window. Please reply to this submission with the reviewer email and we will send an internal-test TestFlight invitation as soon as the build is ready.

---

## After approval

When Apple grants the entitlement (you'll get an email confirming the App ID has been updated):

1. In Apple Developer portal → Certificates, Identifiers & Profiles → Identifiers → `Res.CareCircle`, confirm the "Critical Alerts" capability is now enabled.
2. Regenerate the provisioning profiles for development, ad-hoc, and App Store distribution (the App ID change won't propagate to existing profiles).
3. Add the entitlement key to `CareCircle/CareCircle.entitlements` (currently absent — adding it before approval would fail provisioning):
   ```xml
   <key>com.apple.developer.usernotifications.critical-alerts</key>
   <true/>
   ```
4. Request `criticalAlert` authorization in the iOS notification permission flow:
   ```swift
   try await UNUserNotificationCenter.current().requestAuthorization(
       options: [.alert, .badge, .sound, .criticalAlert, .timeSensitive]
   )
   ```
5. When scheduling the SOS / missed-critical-med notifications, set `content.interruptionLevel = .critical` and `content.sound = .defaultCritical` (or `.criticalSoundNamed(...)` for a custom sound).
6. Update CLAUDE.md "Project configuration facts" line — replace the "application filed" note with "Critical Alerts entitlement granted YYYY-MM-DD".

---

## Tracking

- **Filed:** _(fill in date when submission goes out)_
- **Apple case ID:** _(from confirmation email)_
- **Status:** _(pending / approved / denied / additional info requested)_
- **Approved on:** _(fill in)_
