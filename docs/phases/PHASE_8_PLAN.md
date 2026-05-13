# Phase 8 — Shared calendar + appointments (EventKit)

## Scope
Per spec §4.1 ("Calendar (full view)" lives in More tab) and §4.2 ("medication and appointment tracking"). Phase 8 ships:

- A new `Appointment` SwiftData model per Circle (CloudKit-friendly: defaults on all stored properties, no `@Attribute(.unique)`, inverse relationship to `Circle`).
- Add / edit / delete UI in a sheet form, including transport assignee picker pulling from the Circle's members.
- A list view grouped by Today / Upcoming / Past, with a floating add button matching the meds list affordance.
- A detail view that includes prep notes + visit summary fields (the spec's two non-PHI captures that motivate visit-summary PDFs in a later phase).
- `UNUserNotificationCenter` reminders driven by per-appointment offset list (default `[1440, 60]` per the DB spec — 1 day and 1 hour before).
- Opt-in EventKit mirror: when the user toggles "Add to system Calendar" on an appointment, write a corresponding `EKEvent` and store its identifier. Update/delete the `EKEvent` when the appointment changes or is removed. Requires `NSCalendarsUsageDescription`.
- A new `TodayView` body that shows today's appointments + today's medication doses on a unified timeline, replacing the empty-state stub.
- Calendar entry point under MoreView's "Your Circle" section.

Live Activities for in-progress appointments are explicitly deferred (same Widget Extension constraint as Phase 7).

## Hard constraints
- No Xcode UI edits. New `.swift` files auto-include via the synchronized root.
- `Info.plist` is a build-settings membership exception, but it accepts key/value additions via direct edit as long as Xcode's Info tab hasn't been used since. Add `NSCalendarsUsageDescription` and `NSContactsUsageDescription` (not yet needed) — only add what we use.
- EventKit on Swift 6 strict concurrency: `EKEventStore` is not `Sendable`. Keep all EventKit calls on the main actor and avoid holding references across actor hops.

## Build sequence
1. Model layer: `Appointment.swift` + `AppointmentReminder.swift` (typealias struct for reminder offsets serialization). Update `Circle.swift` with the inverse relationship. Build.
2. `AppointmentReminderScheduler.swift` mirroring `MedicationReminderScheduler` (category `APPOINTMENT_REMINDER`, action `APPT_VIEW`). Build.
3. `AppointmentCalendarSync.swift` — thin EventKit wrapper (`requestAccess`, `upsert(event:from:)`, `delete(eventID:)`). Build.
4. `AppointmentDraft.swift` scratchpad + validation. Build.
5. `AppointmentListView` + `AppointmentRowView`. Build.
6. `AddAppointmentView` (form sheet, transport picker, calendar-sync toggle). Build.
7. `AppointmentDetailView` (edit/delete, prep notes, visit summary, "Mark complete" toggle). Build.
8. Rewrite `TodayView` to merge today's appointments + today's doses on a sorted timeline. Build.
9. Add Calendar NavLink to `MoreView`. Build.
10. `Info.plist`: add `NSCalendarsUsageDescription`. Build.
11. swiftformat + swiftlint. Clean.
12. Commit + push.

## Data model sketch
```swift
@Model
final class Appointment {
    var id = UUID()
    var title = ""
    var provider: String?
    var location: String?
    var startsAt = Date.now
    var durationMinutes: Int = 60
    var prepNotes: String?
    var visitSummary: String?
    var transportResponsibleAppleUserID: String?
    var transportResponsibleDisplayName: String?
    var reminderOffsetsMinutes: [Int] = [1440, 60]
    var ekEventIdentifier: String?
    var completedAt: Date?
    var createdAt = Date.now
    var updatedAt = Date.now
    var circle: Circle?
}
```

## Conflict resolution
Last-write-wins on Appointment fields; `ekEventIdentifier` is per-device (don't sync via CloudKit since EKEvent IDs are device-scoped). Add `@Attribute(.transient)` on `ekEventIdentifier` so it doesn't propagate.

## Validation
- Title required.
- `startsAt` may be in the past (visit summary entry).
- `durationMinutes` in 5...720 (5 min to 12 hours).
- `reminderOffsetsMinutes`: only future offsets relative to `startsAt`. UI gates this.

## Notes
- Disclaimer footer is **not** required for appointments — the "consult your healthcare provider" footer is a meds-only spec rule (§5.6).
- Visit summary text is the seed for the future PDF generator in Phase 12.
