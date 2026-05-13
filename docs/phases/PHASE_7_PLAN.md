# Phase 7 — Medication tracker (manual + label scan + reminders)

**Goal (from build prompt):** Members can add medications manually or by scanning a prescription label with VisionKit's `DataScannerViewController`. Reminders fire on schedule via `UNUserNotificationCenter`. "Mark taken" works from the meds list and from notification actions. Missed-dose grace + escalation logic surfaces overdue items. openFDA ingredient lookup adds context. Disclaimers per spec §5.6 on every medication surface.

## Scope (do)

1. SwiftData models:
   - `Medication`: name, dosage, form, scheduleJSON, instructions, color, status (active/asNeeded/discontinued), startDate, endDate, fdaIngredients (array), createdAt, soft `circle` back-ref.
   - `DoseEvent`: medication back-ref, scheduledAt, takenAt?, markedByAppleUserID?, status (scheduled/taken/skipped/missed/late), notes.
2. Schedule value type: `MedicationSchedule` Codable — `frequency` (daily/weekly/asNeeded), `timesOfDay: [DateComponents]` (hour/minute pairs), `daysOfWeek: Set<Int>?` (1=Sun…7=Sat). Helper computes upcoming `next(occurrencesAfter:limit:)`.
3. Manual add form: name, dose, form picker, schedule editor (frequency + times-of-day rows the user can add/remove), instructions, color tag.
4. Label scan: `DataScannerViewController` (text + barcode) wrapped in a `UIViewControllerRepresentable`. On detect, parse candidate text into `MedicationLabelParser.Suggestion { name, dosage, instructions }`. Camera permission flow.
5. openFDA client: `OpenFDAClient` with `lookupIngredients(name:)` → `[String]`. Plain `URLSession` GET, decode `results.openfda.generic_name`. Failures swallowed (best-effort).
6. Meds tab: list grouped by status; each row shows name, dose, next dose chip; tap → detail.
7. Med detail: schedule summary, ingredients (if fetched), upcoming/past dose events, mark-taken / mark-skipped actions, edit + delete.
8. Notifications: `MedicationReminderScheduler` builds `UNNotificationRequest` for each scheduled time across the next 14 days (calendar trigger; OS limits 64 pending). Actions on the notification: "Taken" / "Skip". Notification delegate maps the action back to a DoseEvent.
9. Missed grace: a periodic `MedicationOverdueSweeper` (runs on app foreground) marks any `scheduled` doses older than `gracePeriodMinutes = 60` as `missed`.
10. Disclaimers: spec §5.6 footer on the meds list, add form, detail view, and openFDA ingredients section.
11. Activity feed: marking taken/skipped posts a `medTaken` Activity into the feed (existing ActivityType already includes `.medTaken`).

## Out of scope (this chunk)

- **Live Activities on lock screen.** Requires a Widget Extension target — only the user can create that in Xcode. Documented at the end of this plan as a follow-up: once the target exists, we'll add `ActivityKit` widgets.
- **Critical Alert entitlement.** Phase 10 work.
- **Cross-circle sync edge cases** (concurrent edits to a schedule). Last-write-wins via SwiftData; CloudKit conflict resolution is fine for v1.

## Architecture

```
Sources/Models/
  Medication.swift                       # @Model
  DoseEvent.swift                        # @Model
  MedicationSchedule.swift               # Codable value type
  MedicationStatus.swift, MedicationForm.swift, DoseStatus.swift

Sources/Services/Medications/
  MedicationReminderScheduler.swift      # UNUserNotificationCenter wrapper
  MedicationOverdueSweeper.swift         # bulk update missed doses
  MedicationLabelParser.swift            # text → suggestion
  OpenFDAClient.swift                    # URLSession lookup
  MedicationNotificationDelegate.swift   # UNUserNotificationCenterDelegate

Sources/Features/Medications/
  MedsView.swift                         # existing stub gets replaced
  MedicationListView.swift               # grouped list
  MedicationRowView.swift                # row card
  MedicationDetailView.swift             # detail
  AddMedicationView.swift                # manual form
  EditMedicationView.swift               # edit existing
  MedicationScheduleEditor.swift         # times-of-day editor
  MedicationLabelScannerView.swift       # UIViewControllerRepresentable
  MedicationDisclaimerFooter.swift       # reusable footer
```

The notification delegate is set in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.

## Build sequence

1. Models + value types (Medication, DoseEvent, MedicationSchedule, enums). Build.
2. `MedicationDisclaimerFooter`. Build.
3. Reminder scheduler stub + delegate stub. Build.
4. Manual add form. Build.
5. Meds list + row + detail. Build.
6. Wire delete/edit + dose marking + feed entry. Build.
7. Overdue sweeper + activate on `.scenePhase` change. Build.
8. openFDA client. Build.
9. Label scanner (VisionKit). Build.
10. swiftformat + swiftlint clean.
11. Commit + push.

## Risks

- **UNUserNotificationCenter 64-request cap.** We schedule 14 days × N times per med, then top up on app foreground. Sweep removes past requests.
- **DataScannerViewController iOS support.** It requires `DataScannerViewController.isSupported`. Older / unsupported devices show a fallback "Type in the label manually" view.
- **openFDA rate limits.** Anonymous keys are 240 req/min; we lookup once per medication on create and cache the result on the model. No per-screen call.
- **Background scheduling.** UNUserNotificationCenter delivers without background time; no extra entitlement needed. Schedule on save.
- **Privacy:** the disclaimer must be visible (not collapsed) on every medication surface per spec §5.6.

## DoD

- xcodebuild green; swiftformat + swiftlint clean.
- Add med form saves a med and schedules notifications when permission granted.
- Tapping a notification action ("Taken" / "Skip") marks the DoseEvent.
- Meds list shows status grouping with disclaimer footer.
- VisionKit scanner pre-fills name + dose on supported devices; unsupported devices fall back gracefully.
- openFDA ingredients appear when lookup succeeds, never block the UI on failure.
- Activity feed shows a "med taken" entry on mark-taken.

## Live-Activity follow-up (after Widget Extension target exists)

When the user creates a Widget Extension target named `CareCircleWidgets` (File ▸ New ▸ Target ▸ Widget Extension), add:
- `MedicationDoseAttributes: ActivityAttributes` (med name, scheduled time)
- `MedicationDoseWidget` LiveActivity view with "Taken" button
- `LiveActivityCoordinator` starts/ends activities from the scheduler

That work is deferred until the target exists; the main tracker is fully usable without it.
