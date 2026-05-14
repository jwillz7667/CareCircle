# Phase 31 — Smart insights engine

**Goal:** Surface system-derived observations about a Circle's care patterns. Each *insight* is a one-card observation ("Evening doses tend to run 25 minutes late — move reminder?") computed locally from existing dose/journal/vital data. The user can dismiss insights they don't find useful, or apply them when the insight has an actionable CTA.

**Scope (MVP):** Two pattern detectors ship in Phase 31 — `doseTimingDrift` and `missedDoseRisk`. Both run off existing `Medication` + `DoseEvent` data. Three more patterns (`moodTrend`, `vitalOutOfRange`, `sleepDecline`) require Phases 33 (vitals) and 34 (journal) to land first; their kinds are reserved in the enum but their detectors are not wired in this phase. A Phase 35 follow-up activates them.

**Non-scope:** No backend storage. Insights are per-device — different caregivers may want different observations bubbled up. No CloudKit sharing. No realtime sync. The data driving insights is already synced; the *derived view* is local.

---

## Files

### New (iOS only)

```
CareCircle/Sources/Models/Insight.swift                                    @Model
CareCircle/Sources/Models/InsightKind.swift                                enum + Severity
CareCircle/Sources/Services/Insights/InsightsEngine.swift                  recompute orchestrator
CareCircle/Sources/Services/Insights/InsightPattern.swift                  protocol
CareCircle/Sources/Services/Insights/Patterns/DoseTimingDriftPattern.swift
CareCircle/Sources/Services/Insights/Patterns/MissedDoseRiskPattern.swift
CareCircle/Sources/Features/Insights/InsightsView.swift                    standalone screen
CareCircle/Sources/Features/Insights/InsightsBanner.swift                  embed on Today
CareCircle/Sources/Features/Insights/InsightCard.swift                     row UI
```

### Amended

```
CareCircle/Sources/Models/Circle.swift                                     // + insights to-many
CareCircle/Sources/App/CareCircleApp.swift                                 // register Insight in schema + inject InsightsEngine
CareCircle/Sources/Features/Today/TodayView.swift                          // surface InsightsBanner
CareCircle/Sources/Features/More/MoreView.swift                            // entry to InsightsView (full list)
CareCircle/Sources/Features/Meds/MedicationDetailView.swift                // accept "apply" CTA from DoseTimingDrift insight
```

### Tests

None — UI tests forbidden until user approves; unit-test target doesn't exist yet (`CareCircleTests/` exists but isn't wired). Pattern detectors have no I/O, so they're unit-testable in principle when the target lands. Phase 31 ships with a manual simulator pass; the audit step in DOD inspects state.

---

## Model

```swift
@Model
final class Insight {
    @Attribute(.unique) var id: UUID
    var kindRaw: String              // InsightKind raw value
    var severityRaw: String          // InsightSeverity raw value
    var subjectKind: String          // "medication" | "careRecipient" | "vital"
    var subjectId: UUID?
    var title: String                // ≤80 chars, plain language
    var body: String                 // ≤240 chars, explains the observation
    var computedAt: Date
    var dismissedAt: Date?
    var appliedAt: Date?             // for CTA insights; set when user takes the suggested action
    var circle: Circle?
    // dedupeKey is computed from kind + subject so the engine can upsert
    // safely across recomputes. Stored to make Predicate fetches O(1).
    var dedupeKey: String
}

enum InsightKind: String, CaseIterable, Sendable {
    case doseTimingDrift = "dose_timing_drift"
    case missedDoseRisk  = "missed_dose_risk"
    case moodTrend       = "mood_trend"        // reserved; not emitted in Phase 31
    case vitalOutOfRange = "vital_out_of_range" // reserved; not emitted in Phase 31
    case sleepDecline    = "sleep_decline"     // reserved; not emitted in Phase 31
}

enum InsightSeverity: String, CaseIterable, Sendable {
    case info        // neutral observation
    case suggestion  // soft CTA
    case warning     // user should look
}
```

`dedupeKey = "<kind>:<subjectKind>:<subjectId|nil>"` — e.g., `"dose_timing_drift:medication:6F1B...A2"`.

---

## Engine

```swift
@Observable @MainActor
final class InsightsEngine {
    private(set) var lastRecomputedAt: Date?
    private(set) var lastError: String?
    private let debouncer = TaskDebouncer(delay: .seconds(5))
    private let patterns: [any InsightPattern]

    init(patterns: [any InsightPattern] = InsightsEngine.defaultPatterns) {
        self.patterns = patterns
    }

    static var defaultPatterns: [any InsightPattern] {
        [DoseTimingDriftPattern(), MissedDoseRiskPattern()]
    }

    func recompute(circle: Circle, modelContext: ModelContext) async {
        var derived: [DerivedInsight] = []
        for pattern in patterns {
            derived.append(contentsOf: pattern.derive(from: circle))
        }
        upsert(derived, circle: circle, modelContext: modelContext)
        markStale(currentKeys: Set(derived.map(\.dedupeKey)), circle: circle, modelContext: modelContext)
        lastRecomputedAt = .now
    }

    func recomputeDebounced(circle: Circle, modelContext: ModelContext) {
        debouncer.schedule { [weak self] in
            await self?.recompute(circle: circle, modelContext: modelContext)
        }
    }
}
```

`DerivedInsight` is a transient value type containing the same fields as `Insight` minus the persistence ID; the engine maps it to a new or existing row by `dedupeKey`.

`markStale` does NOT delete rows with a non-nil `dismissedAt` (those stay dismissed forever) and does NOT delete rows where `appliedAt != nil` (those stay as a record of action taken). Rows that the latest recompute didn't surface AND that were not dismissed/applied get their `appliedAt` set to "now" with `.appliedAt = .now` so they archive cleanly.

---

## Trigger surface

| Trigger | Where |
|---|---|
| App foreground (scenePhase → .active) | `RootView.onChange(of: scenePhase)` |
| Dose event saved | `SyncEngine` post-save hook (debounced 5s) |
| Manual refresh | Pull-to-refresh on `InsightsView` |

App-startup-only is too coarse; per-save is too noisy. The debounced approach captures rapid edit sequences (e.g., logging three doses in a row) as one recompute.

The per-save hook lives in `SyncEngine.commit()` — same place that already broadcasts CloudKit changes. SwiftData's `ModelContext.didSave` is a noisy global observer; we'd rather call the engine deliberately from the same chokepoints that already coordinate persistence.

---

## Patterns

### DoseTimingDriftPattern
For each `Medication` that has `reminderTime != nil`:
1. Collect `DoseEvent`s in the last 14 days with status `.taken` or `.late`.
2. Skip if fewer than 7 events (insufficient signal).
3. Compute `offset = takenAt - scheduledAt` for each event (seconds).
4. Compute median offset.
5. If median > +30 min: emit insight (taking late).
6. If median < -30 min: emit insight (taking early — less common but possible).

Title: `"<medication> typically taken <X> min late"` (e.g., "Atorvastatin typically taken 38 min late").
Body: `"Looking at your last 14 days, you usually take this <X> minutes after the reminder. Would you like to move the reminder?"`
Severity: `.suggestion`. Subject: `medication`. Has an apply CTA that opens `MedicationDetailView` with the reminder time pre-filled to the suggested new time.

### MissedDoseRiskPattern
For each `Medication`:
1. Collect `DoseEvent`s in the last 14 days with status `.missed` or `.skipped`.
2. Group by scheduled hour-of-day (e.g., "8 AM bucket", "8 PM bucket"). (Day-of-week is too sparse; hour-of-day captures "the morning dose" pattern.)
3. If any hour bucket has ≥3 missed in 14 days: emit insight for that medication.

Title: `"<medication> missed <N> times this week"`.
Body: `"The <morning|evening> dose was missed or skipped <N> times in the last 14 days. Consider an alternative reminder strategy."`
Severity: `.warning`. Subject: `medication`. No apply CTA (no single action to take); user can dismiss.

---

## UI

### InsightsView (full list)
- Sectioned by severity: Warnings → Suggestions → Info.
- Each card: icon (kind-specific SF Symbol), title, body, severity-tinted left border.
- Swipe-to-dismiss → sets `dismissedAt`. Dismissed insights don't reappear unless the engine emits a *new* insight with a different `dedupeKey` (e.g., a different medication).
- "Apply" button on cards that have an apply target — opens the target detail view.
- Pull-to-refresh: calls `engine.recompute(circle:modelContext:)`.
- Empty state: "Nothing to share right now. Insights appear as the system spots patterns in your Circle's medication tracking."

### InsightsBanner (embedded)
- Top of `TodayView`, between the digest preview and the date strip.
- Shows the single highest-severity un-dismissed insight (warning > suggestion > info; ties broken by most recent `computedAt`).
- Tappable → navigates to `InsightsView`.
- Hides entirely if no insights, no badge, no padding.

### Entry from More tab
- `Label("Insights", systemImage: "sparkles")` row in "Your Circle" section.
- Badge count of un-dismissed un-applied insights.

---

## Engineering notes

1. **`TaskDebouncer` is new** — small `actor` utility. Schedules a task; subsequent calls within the delay cancel the previous schedule and reset the timer. Used here and reusable for the journal autosave in Phase 34. Lives at `CareCircle/Sources/Core/TaskDebouncer.swift`.

2. **Per-device only** means: when a caregiver dismisses an insight on their phone, the dismissal is local. Another caregiver in the same Circle sees the insight on their phone independently. Acceptable — the spec is explicit that "different caregivers may find different insights relevant." Documented inline.

3. **Schema migration is lightweight.** Adding a new `@Model` doesn't break SwiftData's automatic migration as long as the new model has no required relationship to existing data. `Insight.circle` is optional. Tested by running the app once before the change, once after.

4. **No analytics, no logging of insight content.** Insights are derived from PHI-adjacent data (medication names, dose times). They don't leave the device.

5. **No insight banner on first launch.** Engine is gated on `circle.medications.count > 0` AND `circle.activities.count > 0` — there's no signal worth showing in an empty Circle.

---

## DOD

- [ ] Build clean on iPhone 16 Pro Max simulator.
- [ ] swiftformat + swiftlint clean across all touched files.
- [ ] Manual simulator pass:
  - [ ] Create Circle, add medication with reminder, log 8 dose events late by 30+ min. See insight.
  - [ ] Mark medication missed 3+ times in same slot. See warning.
  - [ ] Dismiss insight, confirm it doesn't reappear after re-foreground.
  - [ ] Apply insight, confirm `MedicationDetailView` opens with pre-filled reminder.
- [ ] Audit pass on all new files (force-unwraps, accessibility, copy).
- [ ] Conventional-commits message: `feat(ios): smart insights engine — dose-timing drift + missed-dose risk (Phase 31)`.
