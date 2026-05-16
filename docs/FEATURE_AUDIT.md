# CareCircle — Feature Audit

Companion to `DASHBOARD_DESIGN_PROMPT.md`. Decides what stays, what folds, what dies. The product strategy is to win on three wedges (A: Family Brain, B: Medication Safety, E: Pulse Intelligence) and let everything else be quietly competent or absent.

The discipline of cutting is harder than the work of building. This document is the cut list.

## Strategy recap

- **A — Family Brain.** Structured, searchable, multi-author record of care decisions, doctor conversations, advance directives, family agreements. The thing that survives any single caregiver.
- **B — Medication Safety.** Active safety system. Interactions, missed-dose escalation, refill orchestration, adherence truth. Not a list, a system.
- **E — Pulse Intelligence.** On-device Foundation Models surfacing meaningful patterns and producing appointment prep + debrief. Conservative confidence thresholds.

Build order: B → E → A. Each lays substrate for the next.

## Decision matrix

| Feature | Decision | Becomes | Rationale |
|---|---|---|---|
| Auth | **Keep** | Auth | Required scaffolding. No change. |
| Circle | **Keep** | Circle | The entity. No change. |
| Members | **Keep** | Members | The entity. Lives in More. |
| Paywall | **Keep** | Paywall | Required for B2C model. No change. |
| Meds | **Rebuild as B** | MedSafety | Rebuild around interactions / escalation / refills / adherence. Not a CRUD list. |
| Pulse | **Rebuild as E** | Pulse | Surface for intelligence. Today screen pulls the headline insight from here. |
| Vitals | **Keep data, demote UI** | (lives in Pulse) | Data layer stays. Standalone vitals tab dies — vitals are intelligence substrate, not a destination. History archive available in More. |
| Insights | **Fold into Pulse (E)** | (deleted folder) | Insights *are* what E produces. Remove the parallel surface. |
| Appointments | **Keep + integrate with E** | Appointments | Becomes Pulse's companion: prep-sheet generator + post-visit debrief. |
| HealthRecords | **Keep as data source** | HealthRecords | Apple Health import substrate. UI surfaces in Brain (records section) and Meds (current prescriptions). |
| Documents | **Keep narrow** | Documents | Narrowed to the ER-brief backbone (POA, advance directive, insurance, recent labs). Surfaces in Brain. |
| EmergencyContacts | **Keep** | EmergencyContacts | Feeds SOS + ER brief. Lives in Brain → "if I'm not reachable" section. |
| SOS | **Keep, de-emphasize on Home** | SOS | Moves off the home screen visually. Lock-screen widget + Today header icon + (eventual) Apple Watch side-button. The home should not be dominated by SOS. |
| Shifts | **Keep, secondary** | Shifts | Feeds Today's "who's on duty" strip. Standalone surface in More. |
| CareMinutes | **Keep, secondary** | CareMinutes | The sibling load-balance feature. Lives in More; ring data may surface in Brain summaries. Not a primary tab. |
| Activity | **Fold into Brain (A)** | (becomes Brain feed) | The activity feed is essentially A's read surface. Rename the entry point; reuse the engine. |
| Journal | **Fold into Brain (A)** | (note template) | The daily check-in becomes a Brain note template ("Daily observation"). Stop maintaining a parallel system. |
| Home | **Replace with HomeDashboardView** | Today | Current Home is a stack of widgets without composition. Replace with the dashboard from `DASHBOARD_DESIGN_PROMPT.md`. Tab renamed Today. |
| Today | **Keep narrow** | (today's check-in component) | Currently the "today's check-in" surface. Becomes a component used inside the new Today dashboard; doesn't own a tab. |
| More | **Keep, expanded** | More | Absorbs everything not primary: subscription, settings, history archives, members, documents, shifts, care minutes, location, vitals history, sign out. |
| Chat | **Kill** | (delete) | Family group chat already exists in Messages, WhatsApp, iMessage. We can't beat them and shouldn't try. Routine chat lives where it already lives; A captures the parts that matter long-term. |
| DirectMessages | **Kill** | (delete) | Same reason as Chat. Private messages between Circle members are a group-chat split-screen problem we don't need to solve. |
| SimplifiedMode | **Kill or rethink** | (defer decision) | A separate UI mode for the Care Recipient. In practice: mild impairment uses iOS accessibility; severe impairment doesn't use the app. The mode adds complexity that doesn't serve the wedges. Recommend killing in this refactor; if there's evidence of Care Recipient adoption, revisit as an Accessibility preference, not a mode. |
| Location | **Keep narrow, move to More** | Location | "Is she safe / where is she" is real but small. Single surface in More + permission flow + map. Not a tab. |

## What ships in the new tab bar

```
[ Today ]   [ Meds ]   [ Brain ]   [ More ]
```

Four tabs, not three — More is necessary plumbing, not a primary surface. The three *primary* tabs map 1:1 to the wedges:

- **Today** = the synthesis screen. Pulls from B + E + A.
- **Meds** = B. Owns medication safety.
- **Brain** = A. Owns the shared record.

E does not get a tab. It is the synthesis voice that surfaces inside Today and feeds Appointments + Meds + Brain.

## What gets nuked from the More tab

The current More tab is a junk drawer. Trim aggressively. Keep only:

- Your Circle (entity detail)
- Care planning: Calendar (appointments), Care load (CareMinutes)
- Records: Documents, Health Records (Apple Health), Vitals history (read-only archive)
- Safety: Emergency contacts, SOS history, Find on map (Location)
- Account: Subscription, Sign out
- About: Version, Help & Support

Killed from More:

- Shift digests (replaced by Shifts → "who's on duty" in Today + standalone in More)
- Symptom journal (folded into Brain)
- Direct messages (killed)
- Insights (folded into Pulse/Today)
- Simplified mode (killed pending evidence)

## Migration plan summary

**This refactor (now):**

1. New design tokens (typography, motion, haptics, semantic colors).
2. AppTab → `today / meds / brain / more`.
3. New `HomeDashboardView` (Today tab content).
4. New `BrainView` shell (Brain tab content) — initial pass reuses `ActivityFeedView` as the feed.
5. `MoreView` updated to absorb the previously-primary Vitals + Wall (Chat) entries, since they no longer have their own tabs.
6. Old `HomeView`, `ChatRoomView`, and `DirectThreadListView` stay in the codebase for now (referenced from More or vestigial) — defer file deletions to the next pass once nothing references them.

**Next sessions (sequenced):**

7. Build B — medication safety system (interactions, escalation, refills, adherence).
8. Build E — Pulse intelligence with calibrated confidence + appointment companion.
9. Build A — Brain templates, decision history, ER-brief generator.
10. Delete the killed folders once their references are gone (Chat, DirectMessages, SimplifiedMode).

## Risks of cutting

- **CareMinutes / Shifts users may notice the demotion.** Keep them functional in More. Don't remove the surfaces, only their primary-tab status.
- **DirectMessages users (if any) lose a feature.** Backend tables stay; UI removed. Migration note in the next release.
- **SimplifiedMode removal needs evidence first.** If telemetry (once added) shows real Care Recipient usage, restore as an Accessibility preference. Don't delete the data model in this pass.
- **Vitals tab demotion may confuse muscle memory.** Add a one-time hint card in Today for the first week pointing to vitals history in More.

## What this refactor is not

- Not a rebuild from scratch. The data layer, services, auth, sync, encryption all stay.
- Not a renaming exercise. Renames are the cheap part; the substance is the resequencing of attention.
- Not a final answer. The wedges (A/B/E) are the bets. Calibrate based on real user behavior once telemetry is in.
