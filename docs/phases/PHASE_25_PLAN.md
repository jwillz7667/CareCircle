# Phase 25 — SOS notification retraction on cancellation

**Status:** shipped
**Started:** 2026-05-13
**Shipped:** 2026-05-13

## What this is

Phase 22 wired up the time-sensitive local SOS notification: when a circle member triggers SOS, every other member's device posts a `UNNotificationRequest` with `interruptionLevel = .timeSensitive` and `sound = .defaultCritical`. Phase 23 then taught the SOS applicator to recognize an UPDATE that flips `canceledAt` from `nil` to a real timestamp — the local `SOSEvent` row is updated, but **the originally-posted notification is left in the delivered tray.**

That means: caregiver A hits SOS, caregiver B's phone alerts. Caregiver A then cancels the alarm on their device. Caregiver B's SwiftData row flips to canceled, but the loud notification sits in their tray, sometimes for hours, looking like an unresolved emergency.

Phase 25 retracts the notification when the cancellation lands. After the SOS merge saves, any rows that transitioned from "active" to "canceled" have their corresponding `UNNotificationRequest` removed from both the delivered queue (`removeDeliveredNotifications(withIdentifiers:)`) and the pending queue (`removePendingNotificationRequests(withIdentifiers:)`), so an unfired scheduled retry — or an undelivered notification that's still in the system's queue — also goes away.

## Why this matters

- **Trust.** A loud SOS that nobody can clear erodes trust in the alert pipeline. The next genuine SOS gets treated as another false alarm.
- **Tray hygiene.** Time-sensitive notifications break through Focus modes; leaving stale ones around defeats the whole point of using that interruption level sparingly.
- **Completes Phase 22's SOS story.** The trigger and the visual UI flip both work; without retraction, the system's third surface (Notification Center) tells a contradicting story.

## End state (definition of done)

1. **`mergeSOSEvents` returns a third bucket: `canceledNotificationIDs`.** Rows that were previously `canceledAt == nil` locally and now have a non-nil `canceledAt` from the response.

2. **`applySosChange` retracts those notifications after save.** Posts a single `removeDeliveredNotifications(withIdentifiers:)` + `removePendingNotificationRequests(withIdentifiers:)` call.

3. **Insert path's notification gate stays as-is.** New events with `canceledAt != nil` in the response (e.g. an SOS that was already canceled before this device synced) are *not* notified for. The existing `shouldNotifyForIncomingSOS` already covers this.

4. **No double-retraction on subsequent UPDATE frames.** Once a row's `canceledAt` is non-nil locally, future UPDATE frames that re-touch the row (e.g. note edits, location-update fields backfilled later) won't re-detect a cancel transition — `mergeSOSEvents` snapshots the local row's pre-merge `canceledAt` to compute the transition before calling `updateSOSEvent`.

5. **Build + lint clean.**

## Architecture

```
mergeSOSEvents(dtos, circle, circleId, modelContext)
  for dto in dtos:
    if let existing = localMap[dtoID]:
      let wasActive = existing.canceledAt == nil
      let nowCanceled = dto.canceledAt != nil
      updateSOSEvent(existing, dto, displayName)
      if wasActive && nowCanceled:
        canceledNotificationIDs.append(sosNotificationID(for: existing.id))
      updatedCount += 1
    else:
      … (insert branch unchanged)
  return SOSMergeResult(insertedRows, updatedCount, canceledNotificationIDs)

applySosChange:
  let merged = mergeSOSEvents(...)
  guard merged.hasWork else { return }
  saveSOSMerge(...)
  retractCanceledSOSNotifications(merged.canceledNotificationIDs)
  for (event, dto) in merged.insertedRows where shouldNotify:
    await postIncomingSOSNotification(event)
```

## Identifier shape

The Phase 22 post site uses identifier `"sos.event.\(event.id.uuidString)"`. We extract this into a tiny helper `sosNotificationID(for:)` and reuse it in both the post path and the new retract path so they can never drift.

## Risks and decisions

- **What if the notification was never posted on this device?** `removeDeliveredNotifications` is a no-op for unknown identifiers. Same for `removePendingNotificationRequests`. No defensive checks needed.

- **What if the SOS was canceled before this device ever saw the insert?** Phase 22's `shouldNotifyForIncomingSOS` already filters this out (returns false when `dto.canceledAt != nil` on the insert path). The user never gets alerted, so there's nothing to retract.

- **What if the device synced while in airplane mode and only sees the canceled state via the cold-start hydration path?** Cold-start hydration goes through `BackendHydrator`, not the realtime applicator. The notification was never posted (no realtime → no `postIncomingSOSNotification` call), so there's nothing to retract. Correct.

- **Per-frame UPDATE that re-fires the cancel branch.** The pre-merge snapshot of `existing.canceledAt` is computed *before* calling `updateSOSEvent`. After `updateSOSEvent` writes the new `canceledAt`, a subsequent UPDATE frame will see `wasActive = false` because the local row was already canceled. No spurious re-retract.

- **Threading.** `UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers:)` is async but does not return a value or throw; it's safe to call from the `@MainActor` applicator with no `await`. Same for `removePendingNotificationRequests`.

- **Cancellation race with the *device that triggered* the cancel.** The device that calls `cancelSOS()` already removes its own notification through the local flow. The realtime fanout to that same device is a no-op because the cancel transition has already been observed locally before the realtime frame arrives. Idempotent.

## Out of scope (deferred follow-ups)

- **Retracting from non-foreground devices.** A device that was force-killed during the SOS window and re-launches will see the canceled state via cold-start hydration but the notification, posted before the kill, may still sit in the tray. Cold-start hydration could mirror the same retraction sweep, but the scope of that fix is a separate phase (it requires the hydrator to compute the same transition signal, and there's a question about which side of the kill the notification was actually posted on). Acceptable v1 behavior.

- **Tray cleanup for non-SOS notification types.** Dose reminders, appointment reminders, and missed-medication escalations have their own lifecycle. Each will need its own retraction logic when those flows ship. Not in scope here.

- **Critical Alert entitlement integration.** The SOS notification still uses `.timeSensitive` because the critical-alert entitlement has not been granted yet. When it lands, the retraction logic does not change — same identifier, same APIs.

## Definition of done checklist

- [x] `SOSMergeResult` gains a `canceledNotificationIDs: [String]` field.
- [x] `mergeSOSEvents` snapshots `wasActive` before update + populates `canceledNotificationIDs`.
- [x] `sosNotificationID(for:)` helper used by both post and retract paths.
- [x] `retractCanceledSOSNotifications` method added that calls `removeDeliveredNotifications` + `removePendingNotificationRequests`.
- [x] `applySosChange` calls retract after `saveSOSMerge` returns true.
- [x] `xcodebuild` clean.
- [x] `swiftformat` + `swiftlint` clean.
- [x] Commit + push under conventional-commit message.

## Open follow-ups (Phase 26+ candidates)

- Cold-start retraction: compute the cancel transition during `BackendHydrator` so stale notifications from before a force-kill get cleared on next launch.
- Generic notification retraction infrastructure used by other notification types (dose, appointment).
- Server-side push notifications for SOS (APNs critical alerts) once the entitlement is granted.
