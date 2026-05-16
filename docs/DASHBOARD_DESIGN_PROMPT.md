# CareCircle — Home Dashboard Design Prompt

A design brief for the redesigned home surface. Hand this to a product designer (or use it directly with a design tool) to produce the new dashboard. Companion to `FEATURE_AUDIT.md`, which decides what belongs in the product at all.

---

## What CareCircle is now

A shared medical cortex for families coordinating care for an aging or chronically ill loved one. Three intertwined capabilities:

- **Family Brain (A)** — the searchable, structured, multi-author record of what the cardiologist said, what the family agreed about hospice, what the advance directive says. The reference that survives any single caregiver burning out, traveling, or dying.
- **Medication Safety (B)** — not a med list, an active safety system. Interaction warnings, missed-dose escalation, refill orchestration, adherence truth (what was actually taken, not what was prescribed).
- **Pulse Intelligence (E)** — on-device Foundation Models analyzing vitals + adherence + appointment history. Surfaces "her resting HR is up 18% over 30 days" only when statistically meaningful. Generates pre-appointment prep sheets and post-appointment debriefs.

These three don't sit on separate tabs. They are **one product viewed from three angles**, and the home dashboard is the surface where they compose.

## The user opening the app

A primary caregiver — adult child, often a daughter, age 40–60, juggling job + own family + caring for a parent with multiple chronic conditions. She opens the app at 7am, at 11pm, during a doctor's appointment, in the hospital lobby, in line at the pharmacy. She is exhausted. She does not have time to learn an app. She wants to know:

1. Is anything wrong right now?
2. What's coming today?
3. What changed since yesterday that I should know?
4. Can I quickly capture the thing I just learned before I forget?

Everything else is secondary.

## What the dashboard's job is

In **one screen, under three seconds of glance**, she should know:

- The status of the person being cared for, this moment.
- What needs attention today, ranked by importance.
- What changed that's worth knowing — both medical (E) and human (A).
- Where to go to act — one tap to log, one tap to read, one tap to escalate.

If the screen takes more than three seconds to parse, it has failed.

---

## Information architecture (the whole app)

The app has exactly **three primary surfaces**, plus a More tray for secondary functions. No fourth tab. Discipline matters more than completeness.

| Tab | Role | What lives here |
|---|---|---|
| **Today** | Synthesized "right now" view | The home dashboard described below |
| **Meds** | Medication safety system (B) | Schedule, adherence, interactions, refills, polypharmacy review |
| **Brain** | Shared family record (A) | Doctor notes, decisions, advance directives, ER-ready brief, family notes searchable across years |
| **More** | Everything secondary | Settings, subscription, members, documents, history archives |

The Pulse intelligence layer (E) is not its own tab — it is the **synthesis voice** that surfaces in Today and informs Meds and Brain.

---

## The Today screen — section by section

A single scrollable surface. No tabs within tabs. Sections appear in this order, top to bottom. Sections collapse gracefully when there's nothing to show — never display an empty placeholder for the sake of the layout.

### 1. Header strip (always visible)

- **Care recipient name + photo** on the left (small, 32pt).
- **Who's on duty today** in the middle (from Shifts; "You" or member name + small avatar).
- **Quiet status dot** on the right: green / amber / red, signaling overall standing this moment. Tap → opens an explanation sheet (why this color).

The header is a single 56pt-tall strip. Not a hero. The dashboard is not about you, it's about her.

### 2. Critical strip (conditional, top-loaded)

Renders only when something genuinely urgent is true. Examples:

- Missed dose of a life-critical med (Eliquis, insulin, anti-rejection drug) in the last 4 hours.
- A vital reading outside the personalized red-zone.
- An active SOS or recent SOS in the last 24h.
- An interaction warning between two newly prescribed meds.

Each item is one row, full-width, with a clear action button. Red surface only when the item is genuinely red. **Most days this section does not render at all.** That's the point — when it's there, it means it.

### 3. Pulse insight (E, one card)

The single most important pattern the on-device model has surfaced **this week**. Examples:

- "Her resting HR has risen 12 bpm over the last 14 days. Consider discussing thyroid panel at the Apr 30 cardiology visit." with two buttons: "Add to appointment prep" + "Dismiss for now."
- "BP volatility correlates with missed evening Eliquis doses (3 of the last 7)." Two buttons: "See doses" + "Discuss with family."
- "No new insights this week." — when nothing meaningful is present. Calm copy, not empty-state-art.

Confidence is the design constraint here: this card must never cry wolf. If the model isn't confident, the card says so plainly and stays quiet.

### 4. Today's plan (B + appointments)

Compact agenda for the next 12 hours:

- Medications due (next 3, with time + dose tap-to-check-off).
- Appointments today or tomorrow morning (with prep-sheet link if generated).
- Scheduled tasks from Shifts (rides, meals, calls).

This is not a full calendar — it is "what's about to happen, in the order it'll happen." Full calendar lives in More.

### 5. What changed (A)

The last 1–3 things added to the Brain that the viewer hasn't seen, in plain-language summary form:

- "Mike added a note from yesterday's neurology visit (3 min read)."
- "Sarah updated the advance directive section."
- "New labs imported from MyChart."

Each row is a single line + author + relative time. Tap opens the entry in the Brain tab. No previews on the home screen — keep it scannable.

### 6. Quick capture (always at bottom-right, floating)

A single floating action button. Tap reveals a quarter-arc of three buttons:

- **Note** — text capture into Brain (with template prompt: visit / decision / observation).
- **Vital** — log a reading, default to most-recent type.
- **Dose** — mark a med dose taken or missed.

No voice button. No SOS button here — SOS lives elsewhere (see below).

### 7. SOS — not on this screen as a giant button

SOS is critical but **does not live on the home screen as a primary visual element.** Its weight there crowds out the dashboard's actual job. Instead:

- A persistent SOS shortcut on the Lock Screen via Live Activity / Control Center widget.
- A small SOS icon in the Today header strip, in muted red, tap-to-confirm.
- The Apple Watch app exposes it on the side button (eventual).

This is a deliberate change from the current Home, where SOS dominates.

---

## Visual language

- **Quiet, calm, confident.** This app is opened during stressful moments. Loud UI raises blood pressure. Whitespace, restraint, considered typography. Think Things 3 or Apple Notes, not a fintech app.
- **Warm, not clinical.** The brand is sage/forest green on warm cream. Adapt the palette for dark mode (deep slate background, sage accents) and high-contrast mode (true black/white with sage accent only).
- **Typography hierarchy with intent.** Three sizes per screen, max. A clear ramp: section header / primary body / supporting caption. All scale with Dynamic Type to AX5 without breaking layout.
- **Cards over walls of text.** Each section is a card with consistent corner radius, padding, and subtle surface tint.
- **Icons earn their place.** SF Symbols only (v1). Every icon paired with a text label. No icon-only buttons.
- **Color signals never alone.** Red/amber/green always paired with a glyph and text. Color-blind users see the same hierarchy.

## Motion language

- **Springs over tweens.** All transitions use `.spring(response: 0.35, dampingFraction: 0.85)` or `.snappy`. No linear or `.easeOut`.
- **Staggered reveals.** When the dashboard first loads, sections cascade in with a 40ms stagger. Subtle.
- **Live updates animate, don't snap.** When a new insight or change-card arrives via WebSocket, it slides in from the top with a soft spring.
- **Reduce Motion respected always.** When `@Environment(\.accessibilityReduceMotion)` is true, all motion becomes opacity crossfade only.

## Haptic language

A taxonomy, not a sprinkling. Use exactly these mappings everywhere:

- `selection` → tab switch, picker change, filter toggle.
- `impact .light` → card tap, row tap.
- `impact .medium` → primary CTA tap (Save, Confirm).
- `success` → dose taken, vital logged, note saved.
- `warning` → about to cancel unsaved work, destructive action confirmation.
- `error` → save failed, network error.

Never trigger haptics during background updates or on app launch — only in response to direct user action.

## Accessibility — mandatory, not optional

- **Dynamic Type to AX5** on every screen. Tested at AX5 before any screen ships.
- **VoiceOver labels + hints + traits** on every interactive element. Test pass: navigate the entire dashboard with eyes closed.
- **44×44pt minimum tap targets** on every tappable element.
- **Reduce Motion** branch on every animation.
- **Reduce Transparency** respected on any blur material.
- **Bold Text** doesn't break layout (test with Larger Text + Bold Text both on).
- **4.5:1 contrast minimum** on body text, 3:1 on large text and UI affordances.

This is non-negotiable. The primary user (older caregiver, often vision-impaired) breaks the moment any of these are skipped.

## States to design

For every section, design the full matrix:

- **Empty** — first-time, no data yet.
- **Loading** — skeleton, not spinner. Skeleton matches the eventual layout.
- **Populated** — the normal case.
- **Stale** — data is older than expected (offline period, sync failed).
- **Error** — clear cause + retry affordance, never a console message.
- **Offline** — banner at the top, cached data clearly marked, write queue indicator.

## Reference apps to study

- **Apple Health (iOS 17+)** — the bar for health data presentation. Study the Summary tab.
- **Things 3** — the bar for clarity, hierarchy, calm.
- **Linear (iOS)** — the bar for typography and density.
- **Calm** — the bar for emotional tone in a wellness/care context.
- **Halide** — the bar for haptic + motion craft.
- **Apple Notes** — the bar for an editor that disappears.

Don't reference: WebMD, MyChart, CaringBridge, Medisafe. They are the bar we are clearing, not aspiring to.

## Anti-patterns — explicit don'ts

- No giant red SOS button on the home screen.
- No tab-bar bloat. Three primary tabs, period.
- No empty-state art for sections that just have nothing to show. Collapse them.
- No spinners as a default loading state. Skeleton rows or nothing.
- No modal alerts for routine errors. Inline + retry.
- No "Welcome!" hero on subsequent visits. The home screen is for the work, not the brand.
- No notifications for things that aren't truly important. Notification fatigue kills trust.
- No marketing copy in the UI ("blazing fast," "elegant," "powerful"). The product speaks through its surface.

## Success criteria

The dashboard is done when:

1. A new user opens it and within 3 seconds says "I get what this app does."
2. An existing user opens it and within 3 seconds knows whether anything needs their attention today.
3. The most-common 3 actions (log dose, log vital, add note) are reachable in 2 taps from cold launch.
4. The screen renders identically clean at default Dynamic Type and at AX5.
5. VoiceOver navigation completes the same 3 actions in equivalent step count.
6. At 11pm in a dark room with brightness at minimum, the screen does not glare.
7. The first sentence a designer reviewing it writes is not "looks fine."
