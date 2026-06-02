# Audit 2026-06-01 — Resolution Log

Disposition of every finding in [`AUDIT_2026-06-01.md`](./AUDIT_2026-06-01.md).
Work was done on branch `fix/audit-2026-06-01` (local). Each fixed item cites
the commit that closed it. Deferred items state *why* and what they depend on.

---

## CRITICAL (P0)

| Finding | Status | Commit / note |
|---|---|---|
| **C1** — `/v1/sync/batch` dead-letter; iOS deletes local op on `queued` | ✅ Fixed | `d31cf7f` — sync-projector worker drains `pending_operations` into domain tables, idempotent on `client_op_id`; local op deleted only on `projected`/`applied`, not `queued`. |
| **C2** — SOS never fans out (routes through C1) | ✅ Fixed | `477cf72` — SOS fires `POST /v1/circles/:id/sos` directly at fire time with its own retry; cancel/resolve wired to the backend cancel route. |
| **C3** — no APNs device-token registration | ✅ Fixed | `477cf72` — `registerForRemoteNotifications`, AppDelegate token callbacks, `POST /v1/me/devices` on launch/auth. |
| **C5** — CI red on every run | ✅ Fixed | `4465730` — eslint + config added; `tsconfig` rootDir fixed; Prisma steps replaced with `@carecircle/migrator`; iOS runner/destination aligned to Xcode 26; meaningful typecheck/lint/test gates. |
| **Zero iOS tests across 34k LOC** | ⚠️ Needs Xcode UI | Test *target* must be created in Xcode (see "Requires the user" below). Pure-logic test plan ready: dose-state transitions, reminder scheduling, SOS, AES-GCM wrap/unwrap, `PHIRedactor`, sleep-dedup, schedule math. |

---

## HIGH (P1)

| Finding | Status | Commit / note |
|---|---|---|
| **C4** — critical-alert push, no entitlement / no fallback | ✅ Fixed | `960bc47` — `critical` gated behind an entitlement flag with a `time-sensitive` fallback. |
| Reminder scheduler caps at 16/med, `.default` sound, no interruption level | ✅ Fixed | `b2544b4` — bounded scheduling across the 64-request app ceiling; interruption level set. |
| Realtime socket authorizes once, freezes membership, token in query string | ✅ Fixed | `6959159` — periodic membership re-check; token moved off the query string. |
| `forget(circleID:)` has zero callers (keys not dropped on member leave) | ✅ Fixed | `a3f402f` — per-circle document keys forgotten on account deletion. |
| Static salt for DEK-wrap key derivation | ✅ Fixed | `a2ed737` — per-circle random salt stored alongside the wrapped keys. |
| Audit-log RLS leaks NULL-circle rows | ✅ Fixed | `37ee3f2` — NULL-circle rows scoped to their actor. |
| No server-side entitlement enforcement | ✅ Fixed | `aba6748` — `requireEntitlement(...)` on premium routes. |
| StoreKit notification handling not idempotent | ✅ Fixed | `69b8a11` — dedupe ledger + monotonic/order-safe guard. |
| PHI redactor misses nicknames / relationship terms / ASR errors | ✅ Fixed | `c9ed43a` — nickname expansion, relationship-term scrub, on-device NER pass; docstring guarantee softened. |
| `documents/upload-url` builds key from unsanitized filename | ✅ Fixed | `862a7db` — filename sanitized. |
| No account deletion / data export | ✅ Fixed | `8efd4b9` (cascading backend delete + export) + `80ef3bf` (in-app Account & Privacy UI — App Store 5.1.1(v)). |
| Worker jobs: no retries / backoff / idempotency / retention | ✅ Fixed | `12ef74b` — `defaultJobOptions` (attempts/backoff/removeOnComplete) + deterministic `jobId`. |
| Route params never validated (500 on bad UUID) | ✅ Fixed | `ae21199` — shared `uuidSchema` params parse → 400. |
| `static let shared` singletons in production views | ✅ Fixed | `dc4533c` — document + calendar services injected via Environment. |
| Dead Chat/DM models in live schema | ✅ Fixed | `c081b13` — Chat/DM feature deleted. |
| No `VersionedSchema` / `SchemaMigrationPlan` | ✅ Fixed | `62615a3` — schema versioned with a migration plan. |
| Whole-table `FetchDescriptor` then filter-in-Swift on `@MainActor` | ✅ Fixed | `5e7e982` — backend-sync local fetches scoped to the circle at the store layer. |
| Cold-launch synchronous sweep fan-out | ✅ Fixed | `ea4bfac` — foreground maintenance deferred off the scene-phase transition. |
| pg Pool `max:10`, no timeouts | ✅ Fixed | `6e6adb3` — connection/statement timeouts set. |
| Sub-13pt fixed `.system(size:)` text won't scale to AX5 | ✅ Fixed | `cb3c38e` — 12 sites converted to text-style `Font.system(_:design:weight:)`. |
| Pulse animations ignore Reduce Motion | ✅ Fixed | `ff71ed0` — `PulseHeroCard` / `BedsideMonitorView` / `WellnessRing` honor Reduce Motion. |
| No remote crash/error telemetry | ✅ Fixed | `b1fb96c` — MetricKit crash + hang diagnostics. |
| **Missed-critical-dose escalation to other caregivers** | ⏸ Deferred | Depends on C1 (now landed). A cross-caregiver escalation chain is a *feature* (audit roadmaps it to NEXT), and the escalation window / recipient order / ack semantics are product decisions, not wiring. Build once those are settled. |
| **Inbound merge is a stub** (skip-if-local-non-empty) | ⏸ Deferred | Blocked on the dual-write iOS→backend migration (a documented future task in CLAUDE.md). No last-writer-wins reconciliation is meaningful until the app writes both paths. |
| **Per-circle document keys stored `ThisDeviceOnly`** | ⏸ Deferred (by design for v1) | The zero-caller `forget()` bug is fixed (`a3f402f`). Changing the keychain accessibility class is a security-sensitive change to the E2EE model and needs explicit product input on the device-sync trust boundary. |
| **Design tokens adopted only on Home** | ⏸ Deferred | LATER per the audit roadmap — a screen-by-screen migration, not a point fix. |

---

## MEDIUM / LOW

| Finding | Status | Commit / note |
|---|---|---|
| Sleep dedup key uses `String.hashValue` (per-process random) | ✅ Already resolved | `HealthKitVitalsReader+Sleep.swift` uses a SHA-256 digest; docstring documents why `hashValue` was wrong. |
| Bedside monitor recomputes full analytics on every 1 Hz tick | ✅ Fixed | `ff71ed0` — clock isolated into a subview; readings memoized per body pass. |
| Invite-code entropy ~40 biased bits | ✅ Fixed | `862a7db` — rejection sampling, ≥128 bits. |
| Prompt-injection: transcript concatenated into the prompt | ✅ Fixed | `3fe6780` — wrapped in a delimited untrusted block. |
| `PATCH /members/:id` allows arbitrary roles / second owner | ✅ Fixed | `3fe6780` — demotion/owner guard. |
| SOS location races authorization on first run | ✅ Fixed | `83296a2` — pre-prompt on arm; wait for the auth callback before the fix. |
| "Always"/background location can't work (missing usage string + bg mode) | ✅ Fixed | `83296a2` — `NSLocationAlwaysAndWhenInUseUsageDescription` + `location` background mode added to Info.plist. |
| Location consent is one global bool, broadcast to all circles | ✅ Fixed | `83296a2` — per-circle opt-in consent; legacy global bool migrated once then dropped. |
| openFDA query double-encoded | ✅ Fixed | `3fe6780`. |
| Comments endpoint unpaginated | ✅ Fixed | `896d19e`. |
| `notification_prefs` column stored but ignored | ✅ Fixed | `f459bb7` — push honors per-circle prefs. |
| No request-id correlation | ✅ Fixed | `9a23cd1`. |
| App-wide `.preferredColorScheme(.light)` | ⏸ Deferred | Coupled to the design-token migration; removing the pin now would expose half-migrated screens to dark mode. Remove when token migration reaches those screens. |
| `new/` untracked design-mockup dir | ✅ Fixed | Moved to `docs/design-mockups/`. |
| CLAUDE.md drift (Prisma / feature-first) | ✅ Fixed | The broken Prisma CI step was fixed in `4465730`; project CLAUDE.md now states **Drizzle ORM (not Prisma)** + layer-based backend layout explicitly. The global `~/.claude/CLAUDE.md` canonical examples are generic defaults, intentionally left untouched. |
| No localization / i18n | ⏸ Out of scope (documented) | Acceptable for US-only v1. |
| Real drug-interaction checking (re-graded HIGH product gap, not a defect) | ⏸ Feature backlog | `InteractionChecker` + UI honestly disclaim same-ingredient-only scope; real DDI surfacing is a Wedge-B feature (openFDA label text, advisory only). |

---

## Requires the user (Xcode UI — cannot be done from the file system)

These are the only remaining items that hard-rule #1 prevents me from doing
(they need `project.pbxproj` / capability changes through the Xcode UI):

1. **Create the iOS Unit Testing Bundle target** — File ▸ New ▸ Target ▸ *Unit Testing Bundle*.
   - Its synchronized root **must** be the top-level `CareCircleTests/` folder (already exists with `Unit/` and `Integration/`), **outside** the app's `CareCircle/` synced root, so test files don't join the app target.
   - Then the pure-logic unit tests (dose/SOS/crypto/redactor/sleep-dedup/schedule math) can land, and a `test` action added to `ios.yml`.
2. **Enable Time Sensitive Notifications** in *Signing & Capabilities* — backs the med-reminder interruption level and the future Critical Alerts entitlement (filed; add `com.apple.developer.usernotifications.critical-alerts` once Apple approves).
