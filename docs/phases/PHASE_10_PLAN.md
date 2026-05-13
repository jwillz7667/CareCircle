# Phase 10 — Emergency SOS

## End state
A big red SOS surface on the Home tab. Triggering it starts a 30-second
countdown (haptics + visual + audio cue) during which the user can cancel.
At T=0 the device records an `SOSEvent` (broadcast via CloudKit to the
rest of the Circle), fires a local critical alert (best-effort —
falls back to time-sensitive if the entitlement is denied), and offers
the user a one-tap call to their primary contact via the system phone
dialer.

## Out-of-scope for this phase
- **Lock Screen widget.** Requires a Widget Extension target that
  only Xcode UI can create. Leave a TODO note and the implementation
  spec; the user adds the target later.
- **True remote critical-alert push to other Circle members without
  the app running.** Needs the Critical Alert entitlement (granted
  case-by-case by Apple) plus a CKSubscription wired with
  `shouldSendContentAvailable` and per-member device-token
  registration. We ship the SwiftData side so propagation happens
  via the normal CloudKit sync; remote-device alerting is a TestFlight-era polish task.
- **VoIP CallKit.** CallKit is for VoIP receivers; we're not building
  VoIP. We dial the primary contact via `tel://` so the system Phone
  app takes over — this is the established Apple-blessed pattern for
  non-VoIP apps.

## Build sequence

1. `SOSEvent.swift` — `@Model`: id, triggeredByAppleUserID,
   triggeredByDisplayName, triggeredAt, latitude/longitude (optional),
   locationAccuracy (optional), canceledAt, canceledByAppleUserID,
   resolutionNotes, circle (inverse). Add `documents`-style `[SOSEvent]`
   inverse to `Circle`.
2. `SOSStatus.swift` — enum {.pending, .firing, .canceled, .resolved} as a computed view on the model.
3. `SOSLocationProvider.swift` — `nonisolated` actor wrapping
   `CLLocationManager`. Requests "When In Use" authorization and grabs
   a single fix (best-effort, 5-second timeout).
4. `SOSNotificationAuthorizer.swift` — requests `.criticalAlert,
   .alert, .sound, .timeSensitive` from `UNUserNotificationCenter`.
   Logs but doesn't error when critical-alert is denied (it's
   entitlement-gated).
5. `SOSCenter.swift` — orchestrator: arm() → 30-second countdown
   (with `Task.sleep` chunks per second so cancel works), fire()
   which captures location + inserts SOSEvent + posts local alert,
   cancel() which writes canceledAt without firing.
6. `SOSCountdownView.swift` — full-screen ZStack with a giant cancel
   button, a ring progress indicator, escalating haptics via
   `UIImpactFeedbackGenerator`, and the seconds-remaining tick.
7. `SOSTriggerButton.swift` — the big red action button used on Home
   and SOSHistoryView. Long-press confirms (3-second hold) to prevent
   pocket-trigger.
8. `SOSDetailView.swift` — shows event metadata, "Call primary
   contact" CTA, resolution notes editor, "Mark resolved" CTA. Shows
   a Map snapshot if location is present (using `MapKit` `Map` view).
9. `SOSHistoryView.swift` — list of prior events with status pills.
10. `HomeView.swift` update — pin SOS trigger above the activity
    feed. Match the spec's "always pinned at top" pattern.
11. `MoreView.swift` update — add SOSHistoryView NavLink under
    "Your Circle" between Calendar and Documents.
12. Primary contact lookup — read first contact with `isPrimary == true`
    from `EmergencyContact`. If none, use the Circle owner's
    `Member.phoneE164` (we don't store member phones yet — for v1, surface
    "Add a primary contact" empty-state with a NavLink to a new
    `EmergencyContactsView` if missing).
13. `EmergencyContact.swift` model + `EmergencyContactsView.swift` —
    simple list + add form. Stored in plaintext for v1 (number + name
    only — not strongly PHI on its own per spec §4.18).
14. `Info.plist` — `NSLocationWhenInUseUsageDescription` (already may
    be present — verify), `NSContactsUsageDescription` (for the
    contact-picker stretch goal, leave a TODO if not needed).
15. swiftformat + swiftlint clean.
16. xcodebuild green.
17. Commit + push.

## Future TODOs left as comments in code
- `SOSCenter`: when Critical Alert entitlement is granted, switch the
  local notification's `interruptionLevel` to `.critical`.
- `SOSCenter`: when a Widget Extension is added, broadcast intent
  via App Group UserDefaults so the widget can read the latest SOS
  state without launching the app.
- `SOSEvent`: add CKSubscription registration in
  `Services/CloudKit/` once the spec's push-fanout strategy is finalized.

## Safety rules (carry-forward)
- No marketing language about being a medical/emergency device.
- The 30-second cancel window is non-negotiable per spec §3.1 #7.
- The countdown must work even when the screen is on and the user is
  interacting with it — escalating haptics every 5 seconds.
- A `tel://` URL is opened via `UIApplication.shared.open` only after
  an explicit user tap; we don't auto-dial.
