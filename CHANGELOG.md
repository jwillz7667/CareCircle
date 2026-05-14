# Changelog

All notable changes to CareCircle are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries are added at the top. The `Unreleased` section accumulates work between releases.

## [Unreleased]

### Added
- **Pulse tab.** New realtime vitals dashboard with hero pulse card, wellness composite (0–100), per-vital tiles with sparklines, anomaly callouts, and entry points to the Bedside Monitor and AI Care Co-pilot.
- **Bedside Monitor.** Ambient full-screen mode with a live ECG-style waveform rendered through SwiftUI Canvas, idle-timer disabled, and oversized numerics for across-the-room glances.
- **AI Care Co-pilot.** On-device deterministic narrator composing a 4–6 sentence brief plus highlights (overdue doses, upcoming appointments, anomaly callouts, open SOS), with `AVSpeechSynthesizer` voice playback and a question/answer field staged for iOS 26 Foundation Models swap-in.
- **Find tab.** Live MapKit-based map of every Circle member's last-known location, with a recipient-locked re-center button, per-member chips, opt-in sharing toggle, and Settings deeplink for permissions.
- **Wall tab.** Circle-wide chat / shared feed with day-grouped bubbles, own-message gradient, copy + delete context menu, and automatic scroll-to-bottom on new messages.
- **VitalsAnalytics service.** Pure on-device statistical engine — per-kind 14-day baseline, z-score anomaly detection, trend computation, and wellness composite. No PHI leaves the device.
- **LocationSharingService.** `@Observable` CoreLocation wrapper that upserts a single `LocationSnapshot` row per `(circle, memberAppleUserID)`. Opt-in per device, UserDefaults-persisted, with significant-change monitoring when authorization is upgraded to "always".
- **ChatMessage @Model.** SwiftData model for the Circle Wall, CloudKit-compatible (all fields defaulted, no `@Attribute(.unique)`), shared-zone propagation.
- **LocationSnapshot @Model.** SwiftData model for live location, overwrite-per-member pattern.
- Professional repository scaffolding: `README.md`, `LICENSE` (proprietary, Viral Venture LLC), `NOTICE`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `.editorconfig`, `.gitattributes`, expanded `.gitignore`, this `CHANGELOG.md`.

### Changed
- `MainTabView` expanded from a 4-tab to a 5-tab layout (Home · Pulse · Find · Wall · More).
- `Circle.swift` gained `locationSnapshotsStore` + `chatMessagesStore` relationships with non-optional computed accessors.
- `CareCircleApp.swift` `Schema` includes `LocationSnapshot` + `ChatMessage`. The app instantiates a `LocationSharingService` and injects it into the SwiftUI environment.

## [Phase 33] — 2026-05-13

### Added
- HealthKit vitals — manual entry path and HK reader skeleton, gated by the HealthKit entitlement.
- Backend `vitals` table with FORCE RLS, encrypted payload columns, and `LISTEN/NOTIFY` fan-out.
- Shared Zod schemas for `createVital`, `vitalKind`, `vitalSource`.
- iOS `Vital` SwiftData model + DTO + mapper + sync + hydrator wiring.

## [Phase 32] — 2026-05-12

### Added
- Pill identifier feature with NDC barcode scanning + ingredient overlap detection.

## [Phase 31] — 2026-05-11

### Added
- Smart insights engine: dose-timing drift detection and missed-dose risk scoring.

## [Phase 30] — 2026-05-10

### Added
- End-of-shift voice digest with on-device summarisation and a cloud inference fallback for older devices.
- Backend inference service routing requests through PHI-stripped proxies.
- `ShiftDigest` SwiftData model + feature views + Today/Activity feed integration.

## [Phase 29] — 2026-05-09

### Added
- Pull-to-refresh on empty-state branches.

## [Phase 28] — 2026-05-08

### Added
- Pull-to-refresh on remaining list views.

## [Phase 27] — 2026-05-07

### Added
- Pull-to-refresh wired to snapshot resync.

## [Phase 26] — 2026-05-06

### Added
- Cold-start SOS notification retraction — pending SOS notifications are cleared from the lock screen on launch if the underlying event is no longer active.

[Unreleased]: https://github.com/jwillz7667/CareCircle/compare/v0.1.0...HEAD
[Phase 33]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-33
[Phase 32]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-32
[Phase 31]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-31
[Phase 30]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-30
[Phase 29]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-29
[Phase 28]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-28
[Phase 27]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-27
[Phase 26]: https://github.com/jwillz7667/CareCircle/releases/tag/phase-26
