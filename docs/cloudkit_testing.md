# CloudKit testing runbook

Last updated: 2026-05-13 (Phase 3 — Members + CKShare).

CareCircle's CloudKit code path has two halves:

1. **Private-database sync** — SwiftData's `ModelConfiguration(cloudKitDatabase: .private(...))` mirrors the owner's data across their own iCloud-signed devices.
2. **CKShare sharing** — `CircleSharingService` creates a `CKShare` rooted on a per-circle `CKRecordZone` and emits a `CKShare.url` for handoff via the system share sheet. Invitees accept the share through `CircleSceneDelegate`'s `windowScene(_:userDidAcceptCloudKitShareWith:)` callback.

Some pieces are testable on the iOS Simulator; CKShare end-to-end is not. This document is the source of truth for what to test where.

---

## What works on the Simulator

| Capability | Status |
|---|---|
| App boots with `.private` CloudKit configuration on a Simulator without iCloud signed in | Works — SwiftData falls back to local-only storage and logs an account-status warning. |
| Create a Circle, edit Care Recipient, add invited Member rows | Works (purely local SwiftData). |
| Open MembersListView, show the Invite button for the owner | Works. |
| 8-member cap enforced when adding members | Works — the form blocks the Send button. |
| Sign in to iCloud on the Simulator | Inconsistent. iOS sims do not reliably accept iCloud sign-in in CI; manual sign-in via Settings ▸ "Sign in to your iPhone" sometimes works on real-hardware-paired sims (Xcode ▸ Window ▸ Devices and Simulators). |
| Open the CKShare URL from iMessage on a Simulator | **Does not work.** Simulators do not resolve CloudKit share URLs even when iCloud is signed in. |
| `windowScene(_:userDidAcceptCloudKitShareWith:)` callback | Cannot be exercised on Simulator. |

---

## Real-device test matrix

Required hardware:

- Two physical iPhones (any model on iOS 26).
- Two **separate** iCloud accounts. Apple ID account A is the Circle owner; account B is the invitee. Use Apple's test-account creation tool if you need disposable IDs.
- Both devices on Wi-Fi (CloudKit zones propagate in ~5–30 seconds; cellular adds variance).
- The Xcode project signed with your team and the entitlements file (`CareCircle/CareCircle.entitlements`) listing `iCloud.Res.CareCircle`.

### Pre-flight check

1. On both devices: **Settings ▸ \[Your name\] ▸ iCloud** — confirm signed in and **iCloud Drive** is on.
2. On both devices: **Settings ▸ \[Your name\] ▸ iCloud ▸ Show All ▸ CareCircle** — toggle on if present.
3. On the Mac: **Xcode ▸ Settings ▸ Accounts ▸ Your team ▸ Manage Certificates** — ensure a development cert exists.
4. Build the app to device A, then to device B (`Cmd-R` in Xcode while each device is selected).

### Happy-path scenario

1. **Device A:** open CareCircle, Sign in with Apple. Tap **Create your Circle**. Enter name "Mom's Care", first name "Eleanor", DOB ~80 yrs ago, conditions "type 2 diabetes". Save.
2. **Device A:** More tab ▸ Your Circle ▸ Members ▸ Invite. Enter display name "Daniel", role "Family member". Tap **Send**.
3. **Device A:** the system share sheet appears with the share URL. Choose **Messages**, send to device B's iMessage account.
4. **Device B:** open Messages, tap the share link.
5. **Device B:** CareCircle launches. After ~5 seconds, the Circle "Mom's Care" appears in **More ▸ Your Circle**.
6. **Device A:** Members list — Daniel's row now shows status "Invited" (we don't yet resolve the share acceptance back into an `.active` row; that's a Phase 4+ concern when we have an activity feed to log "Daniel joined").

### Negative scenarios to verify

- **No iCloud on Device A** — Sign out of iCloud on Device A, attempt Invite. The form surfaces "Sign in to iCloud in Settings to invite Circle members." No `Member(.invited)` row is written. (Local-state hygiene.)
- **9th member** — On Device A, fill the Circle to 8 active+invited members. The 9th Invite attempt: Send button disabled, form footer reads "This Circle is full (8 members)."
- **Bad URL** — On Device B, tap an invalid CKShare URL. iOS surfaces an error; CareCircle does not crash. (`CircleSceneDelegate` simply doesn't receive the callback.)
- **Offline invitee** — On Device B, enable Airplane Mode, then re-enable Wi-Fi after 30 seconds. The Circle should still appear post-sync.

---

## Diagnosing failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `CKError.notAuthenticated` in logs | iCloud not signed in or CareCircle disabled in iCloud settings | Settings ▸ \[Your name\] ▸ iCloud ▸ Show All ▸ CareCircle on |
| `CKError.zoneNotFound` repeatedly | Container identifier mismatch | Verify `iCloud.Res.CareCircle` in entitlements **and** in the Xcode capability |
| Share URL never appears | `CircleSharingService.share(_:)` failed silently | Check OSLog category `cloudkit` via Console.app filtered by `subsystem:Res.CareCircle category:cloudkit` |
| Invitee sees nothing after accepting | SwiftData CloudKit sync hasn't ingested the shared zone | Pull-to-refresh isn't wired yet — wait 30s, force-close, relaunch |
| Owner sees the invited member as "Invited" forever | Expected for v1. We don't yet resolve share acceptance back into an `.active` row for the original placeholder. |

OSLog spelunking:

```bash
# Stream CareCircle's CloudKit logs in real time (from macOS).
log stream --predicate 'subsystem == "Res.CareCircle" AND category == "cloudkit"' --info --debug
```

---

## CKShare implementation notes (for future maintainers)

The current implementation in `CircleSharingService.swift` makes three deliberate choices worth knowing:

1. **One zone per Circle.** `CloudKitConfiguration.recordZoneID(for: circleID)` derives `"circle-<uuid>"`. Custom zones are required because CKShare cannot live in the default zone. Naming on the Circle UUID also lets us cleanly delete a closed Circle.
2. **Owner-side mirror record.** The `CKRecord` typed `Circle` is the share's `rootRecord`. SwiftData's CloudKit sync ignores it (SwiftData manages its own record types); the mirror exists *only* so we have something with a stable record ID to root the share on. Participants see the mirror in their shared database but the actual Circle/Member/CareRecipient data they consume comes from SwiftData's incremental sync.
3. **Idempotent share creation.** `fetchOrCreateShare` looks up an existing share by deterministic record ID (`"share-<circleUUID>"`) before creating one. Re-invoking `share(_:)` for the same Circle returns the same share, so a user re-opening the Invite flow can re-issue the URL without server-side duplication.

We deliberately do **not** call `UICloudSharingController`. The system share sheet (`UIActivityViewController` wrapping `share.url`) is enough for v1, sidesteps the deprecated controller, and produces the same iMessage-rendered share card.
