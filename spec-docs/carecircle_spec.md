# CareCircle — Product Specification

**Working title:** CareCircle
**Category:** iOS app, Health & Fitness / Medical
**Target ship date for v1 (MVP):** ~12 weeks from project start
**Author:** Justin / Product Research Analyst
**Last updated:** May 13, 2026
**Status:** Draft v1.0

---

## 0. How to use this document

This is a complete, build-ready spec. It is structured so you can hand any section to Claude Code or an iOS coding agent and get directly to implementation. Sections that contain explicit AI-prompt-ready scopes are marked **🤖 Agent-ready**.

The spec is intentionally opinionated. Where multiple paths exist, one path is recommended and the alternatives are noted briefly. Vibe-coder reality check: you do not need to make every decision yourself before starting — the spec makes the decisions for you, you can override anything.

---

## 1. Product vision and positioning

### 1.1 One-sentence pitch

**CareCircle is the iOS app that turns chaotic family caregiving — siblings, paid aides, and an aging parent — into a single shared operating system, with voice-first handoffs, medication and appointment tracking, and built-in documentation for state-paid family caregiver programs.**

### 1.2 The problem (grounded in McKinsey research)

From the broader market research report (and supporting public data):

- The US has **53 million unpaid family caregivers** providing an estimated **$3.2 trillion in unpaid labor** (McKinsey Health Institute / AARP).
- The ratio of working-age people per person 65+ is collapsing: **11.7 (1950) → 7 (today) → 4.4 (2040)**.
- Personal care services are projected to grow at **10–12% CAGR through 2028**, partly because of state "fiscal intermediary" programs that pay family members to care for loved ones (McKinsey, "What to expect in US healthcare in 2025 and beyond").
- All 50 states now have some form of Medicaid-funded consumer-directed personal-care assistance program, and most allow adult children to be paid (Medicaid Planning Assistance / MACPAC).
- Caregivers in self-directed programs must maintain **service documentation** to support Medicaid reimbursement, but no consumer-facing app today does this well.
- The everyday caregiver pain points reported in research and forums: medication tracking, sibling alignment, "did anyone go to mom's today?", appointment prep, visit notes, document chaos (insurance cards, advance directives, MyChart logins), and the emotional toll of feeling alone with the responsibility.

### 1.3 Competitive landscape (and where CareCircle wins)

| Competitor | What they do well | Where they fall short |
|---|---|---|
| **Caring Village** | Care plans, document storage, AI assistant "Julia" | Web-first, dated UX, no paid-caregiver documentation, no voice |
| **CaringBridge** | Updates feed for far-flung family | Pure journal/feed, no operational coordination |
| **Lotsa Helping Hands** | Volunteer scheduling for meals/rides | Volunteer-centric, weak on medication and clinical |
| **Medisafe** | Best-in-class medication reminders | Single-person tool, no family circle |
| **CareZone** | Med scanning, document storage | App effectively unmaintained since 2020 |
| **Connected Caregiver** | Bundled with hardware (Prompter pillbox) | Hardware lock-in; weak software |
| **MyChart** (Epic) | Real medical records via proxy access | Per-health-system silos, not family-coordination |
| **Neela** | Newest entrant; AI scribing & summaries | Solo-caregiver focus, no sibling coordination, no paid-caregiver docs |

**CareCircle's positioning** sits in the white space at the intersection of four jobs that no existing app does all at once:

1. **Coordinate the family circle** (siblings + paid aides + the senior)
2. **Capture clinical/operational reality** through fast voice-first handoffs
3. **Generate documentation** that satisfies state fiscal-intermediary paid-caregiver programs (the unique monetization wedge)
4. **Bridge to the clinical world** via printable visit summaries and HealthKit integration

### 1.4 Why now

- **iOS 18+ HealthKit** exposes new data streams (sleep stages, HRV, irregular rhythm notifications, ECG, vitals from BLE peripherals) that make at-home monitoring meaningful.
- **Apple Intelligence + on-device LLMs** (Foundation Models framework, iOS 26+) let you do voice handoff transcription and summarization without paying per-token cloud LLM costs.
- **State self-direction programs are expanding rapidly** — Ohio launched theirs Oct 2024; NY's PPL transition forced 250K+ caregivers to re-enroll in 2025; CMS GUIDE model started July 2024. There is unmet demand for documentation tools.
- **CloudKit** has matured to the point where a small team can run a privacy-first multi-user app **without standing up a backend**.

### 1.5 Non-goals (what CareCircle is NOT)

- Not a telehealth app. Not a HIPAA-covered entity in v1. Not a replacement for MyChart.
- Not a marketplace for hiring caregivers (no liability exposure).
- Not a remote patient monitoring (RPM) device or service.
- Not a dementia-specific tool (dementia is a future expansion).
- Not a medical-advice chatbot.

---

## 2. Target users and personas

### 2.1 Primary persona — "Sarah, the Sandwich Daughter"

- **Age:** 47
- **Lives:** Suburb of a mid-size US city
- **Job:** Marketing manager, hybrid work
- **Situation:** Manages care for her 78-year-old mother who lives 20 minutes away. Has a brother who lives in another state and "checks in" weekly. There is one paid home aide for 15 hours/week.
- **Day-to-day pain:**
  - Texts mom 4–5 times a day to ask if she took her meds
  - Group text with brother that's mostly her venting
  - Tries to remember what the cardiologist said two weeks ago
  - Forgets the new insurance card is in the kitchen drawer when at the pharmacy
  - The aide leaves handwritten notes that Sarah can't always read
- **What she wants:** A single place where everyone — including the aide and mom herself — can see what's happening, and where she can stop being the human router.
- **Willingness to pay:** $10–15/month, will pay annually if there's a discount.

### 2.2 Secondary personas

- **Mark, the Out-of-State Sibling** — wants visibility without being asked, contributes occasional financial support, occasionally feels guilty.
- **Diane, the Paid Aide** — works for two families, uses an Android phone (relevant: forces clean web app or React Native for v2; v1 iOS-only is acceptable).
- **Eleanor, the Care Recipient (78)** — uses an iPhone, knows how to FaceTime, struggles with anything that has more than one screen. Read-only or extremely simple write access.
- **Brenda, the Paid Family Caregiver** (Medicaid self-directed program participant) — Eleanor's other daughter, who quit her job to provide care under Ohio's MyCare Waiver. She gets paid by PPL (the state's fiscal intermediary) and **must document hours and services for Medicaid reimbursement**. This persona is the monetization tier-2 wedge.

### 2.3 The "circle" — relationship model

Every CareCircle is built around exactly **one Care Recipient**. Each circle has Members with roles. A user can be in multiple circles (caring for both parents, or being in someone else's circle while running their own).

Roles (with default permissions):

| Role | Read | Write Activities | Manage Meds | Manage Documents | Manage Circle | Receive Alerts |
|---|---|---|---|---|---|---|
| Care Recipient | ✓ | ✓ (self only) | — | view | — | ✓ |
| Primary Caregiver | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Family Member | ✓ | ✓ | view | view | — | ✓ (configurable) |
| Paid Aide | scoped | ✓ (shifts only) | ✓ (admin during shift) | scoped | — | ✓ during shift |
| Paid Family Caregiver | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| View-Only (e.g. distant relative) | ✓ | — | view | view | — | digest only |

---

## 3. Feature inventory (v1, v2, v3)

### 3.1 v1 (MVP) — ship in ~12 weeks

These are the features required to make CareCircle real and useful to Sarah and her family. **Everything below is in scope for v1.**

1. **Circle creation and invitations**
   - Create a circle around a Care Recipient profile
   - Invite by phone number / email / share link with a 6-digit code
   - Role assignment at invite time
   - Up to 8 members per circle in v1

2. **Shared activity feed**
   - Chronological feed of everything that happens: meds taken, visits, voice notes, photos, appointment notes, alerts
   - Filter by member, type, date
   - Each item is reactable (👍 ❤️ 🙏) and commentable

3. **Voice-first handoff notes** (the defining feature)
   - Big "What happened?" button
   - Record up to 3 min of voice
   - On-device transcription using Speech framework
   - Optional auto-tagging (meds / mood / meals / sleep / vitals / appointments / other) via on-device classification
   - Auto-summary across multiple notes in a day, generated end-of-day, surfaced as a digest

4. **Medication tracker**
   - Add meds manually OR by scanning the prescription label (VisionKit + OCR)
   - Schedule with timezone-safe reminders (use UNUserNotificationCenter, calendar-based triggers)
   - "Mark taken" with one tap on the lock screen Live Activity
   - Missed-dose alerts that escalate to circle members after configurable grace period
   - Drug-interaction warnings via openFDA API lookup (informational, not advice — disclaimer)

5. **Shared calendar**
   - Appointments with reminder cascades to whoever is on transport duty
   - Sync to system calendar via EventKit (one-way: CareCircle → iOS Calendar)
   - Repeating events with smart adjustments (e.g., "every 4th Wednesday")

6. **Document vault**
   - Photos / PDFs of insurance cards, advance directives, DNR, med list, MyChart QR codes, recent EOBs
   - On-device thumbnail rendering, encrypted at rest (CryptoKit)
   - Each member can be granted view/edit per document

7. **Emergency SOS**
   - Big red button on Home tab and as a Lock Screen widget
   - When activated, pings the entire circle with location + a synthesized voice message
   - Triggers a phone call to the designated primary contact via CallKit
   - 30-second cancel window with haptic

8. **Care minutes log** (paid-caregiver feature, monetization tier 2)
   - Manual or auto-detect (when a tagged member arrives at the Care Recipient's home — geofence)
   - Service category picker matching Medicaid HCBS service codes (personal care, meal prep, transportation, medical assistance, etc.)
   - Weekly export as PDF formatted to match common fiscal intermediary timesheet requirements (PPL, Acumen, Easterseals templates as known patterns; this is a "ready-to-submit-with-edits" document, not a direct submission)
   - Disclaimer: caregivers are responsible for verifying that the export matches their specific FI's requirements

9. **Care Recipient simplified view**
   - On-device toggle: when launched on the senior's iPhone with their Apple ID, the app shows a stripped-down 2-button interface: "I took my meds" and "Call for help"
   - Configurable in Settings by the Primary Caregiver

10. **Privacy and consent**
    - Care Recipient must give explicit consent at first launch — multi-step, with audio explanation
    - All data is end-to-end encrypted at rest
    - User can export their entire data history as a ZIP
    - User can delete the circle entirely (full purge from CloudKit)

### 3.2 v2 — months 4–9

- **HealthKit deep integration:** auto-pull medications, blood pressure, glucose, weight, heart rate, sleep, falls, irregular rhythm notifications from Apple Watch
- **Watch app** for the senior: med reminders + fall-detection-relay + "I'm OK" tap
- **AI handoff summarizer:** generates "morning brief" each day combining the previous day's activity into a 2-sentence summary
- **Provider visit summary generator:** before an appointment, the app produces a 1-page PDF of recent activity, vitals, meds taken/missed, and 3 questions to ask the doctor
- **Sibling cost ledger:** light expense tracking and splitting for shared costs (groceries, copays, household help)
- **Web app** for the paid aide (so they don't need an iPhone)
- **HSA/FSA receipt capture** with auto-categorization
- **Multi-circle**: support a user being primary in 2+ circles (caring for both parents)

### 3.3 v3 — months 9–18

- **Android app** (likely React Native or KMP — defer this decision)
- **Hospital discharge mode**: structured intake from After Visit Summary OCR
- **MyChart proxy integration** (FHIR / SMART on FHIR if Epic ecosystem permits)
- **Dementia mode**: behavior tracking with NPI-Q-style structured logging
- **B2B mode for small home-care agencies** (manage multiple clients)
- **Pharmacy refill integration** (CVS, Walgreens, Walmart APIs where available)

---

## 4. User experience and information architecture

### 4.1 App structure (tab bar, iOS 18 style)

```
┌─────────────────────────────────────┐
│              CareCircle             │
├─────────────────────────────────────┤
│                                     │
│        [Main content area]          │
│                                     │
│                                     │
├─────────────────────────────────────┤
│  Home  │  Today  │  Meds  │  More   │
│  🏠    │  📋     │  💊    │  •••    │
└─────────────────────────────────────┘
```

- **Home** — Activity feed + SOS button always pinned at top
- **Today** — Today's schedule (meds, appointments, shifts) in a unified timeline
- **Meds** — Medication list with quick "mark taken" controls
- **More** — Documents, Calendar (full view), Circle members, Settings, Care minutes (if enabled)

### 4.2 Onboarding flow (~3 minutes)

1. Welcome screen with a 15-second illustrated "what this is" carousel
2. Sign in with Apple (mandatory; no email/password)
3. "Who are you setting this up for?" → choose: myself / a parent or relative / a friend
4. If for a relative: create the Care Recipient profile (name, DOB, photo, primary conditions if known — all optional)
5. Invite at least 1 other person (skippable; can do later)
6. Permissions sweep: notifications, contacts (for invites), HealthKit (skippable; explained), location (only when in use, for SOS and geofence), Speech recognition (for voice notes)
7. Done → land on empty Home with a "Record your first handoff" prompt

**Important UX principles:**
- Never force more than one decision per screen
- Never use the word "patient" — use "your loved one" or the Care Recipient's first name
- Provide an "explain why" link next to every permission ask

### 4.3 Voice handoff flow (defining interaction)

This is the hero feature. The flow:

1. From Home, user taps the floating "What happened?" button
2. App immediately starts recording with a clear visual waveform
3. User speaks naturally: "Just got back from mom's. She ate lunch — chicken soup and crackers. BP was 132 over 84 at noon. She mentioned her hip is hurting more on the right side. The aide is coming at 4."
4. User taps Stop (or it auto-stops at 3 min or after 4 seconds of silence)
5. App shows the transcription immediately, with extracted entities highlighted:
   - **Vital**: BP 132/84 at noon
   - **Symptom**: right hip pain, worsening
   - **Meal**: lunch — chicken soup, crackers
   - **Upcoming**: aide at 4 PM
6. User can edit, add a photo, or just tap "Post"
7. The note appears in the activity feed for the whole circle within seconds

**Time from tap to posted: target < 90 seconds total.**

### 4.4 Visual design direction

- **Aesthetic:** Warm, calm, professional. Not childish, not clinical-sterile.
- **Color system:** Soft sage green primary, warm cream backgrounds, deep navy text. Avoid red except for SOS and missed-med alerts.
- **Typography:** SF Pro Display for headers, SF Pro Text for body. Generous line-height. Default body size 17pt; Dynamic Type fully supported up to AX5.
- **Iconography:** SF Symbols throughout. Avoid custom icons in v1.
- **Accessibility (non-negotiable for this audience):**
  - VoiceOver labels on every interactive element
  - Minimum tap target 44×44 pt
  - Contrast ratio 4.5:1 minimum
  - Tested with Dynamic Type at AX5
  - Reduce Motion respected
  - High-contrast mode supported

---

## 5. Technical architecture

### 5.1 Stack overview

| Layer | Choice | Rationale |
|---|---|---|
| Platform | iOS 17.0+ (iOS 18 for Live Activities, iOS 26 for on-device LLMs) | Matches Justin's stack, covers ~95% of active iPhones |
| Language | Swift 5.10+ | Standard |
| UI | SwiftUI (with UIKit interop for VoiceOver edge cases) | Justin's stack |
| Local data | SwiftData | Modern, simple, Justin already uses this on Piggly |
| Sync | CloudKit (private + shared databases) | No backend to run, Apple-grade privacy story |
| Authentication | Sign in with Apple | Required by Apple for SiwA-only apps; clean |
| Voice → text | Apple Speech framework, on-device | Free, private |
| Tagging/summarization | Apple Foundation Models framework (iOS 26+) with fallback to OpenAI gpt-4o-mini | On-device first; cloud only if needed |
| OCR (prescription labels, insurance cards) | VisionKit DataScannerViewController | Native, no cost |
| Drug data | openFDA API | Free, government-maintained |
| Push | APNs via CloudKit silent pushes | Built-in to CKSubscription |
| Analytics | TelemetryDeck or PostHog | Privacy-respecting |
| Crash reporting | Sentry | Justin's preference |
| Subscription | RevenueCat | Industry standard for iOS subs |
| Payments | StoreKit 2 (via RevenueCat) | Required by Apple |

### 5.2 Data model (SwiftData)

```swift
// Core entities. Simplified — see full model in spec appendix A.

@Model
class Circle {
    var id: UUID
    var createdAt: Date
    var name: String                // e.g. "Mom's Care"
    var careRecipient: CareRecipient?
    var members: [Member]
    var subscription: SubscriptionState
    var settings: CircleSettings
}

@Model
class CareRecipient {
    var id: UUID
    var firstName: String
    var lastName: String?
    var dateOfBirth: Date?
    var photo: Data?
    var primaryConditions: [String]
    var emergencyContacts: [EmergencyContact]
    var insuranceCards: [Document]
}

@Model
class Member {
    var id: UUID
    var appleUserID: String          // From Sign in with Apple
    var displayName: String
    var role: MemberRole             // Enum
    var permissions: PermissionSet
    var joinedAt: Date
    var notificationPreferences: NotificationPreferences
}

@Model
class Activity {
    var id: UUID
    var circle: Circle
    var author: Member
    var createdAt: Date
    var type: ActivityType           // .voiceNote, .medTaken, .photo, .visit, .appointment, .alert
    var voiceNote: VoiceNote?
    var photo: Data?
    var text: String?
    var tags: [Tag]
    var extractedEntities: [Entity]  // Parsed from voice/text
    var reactions: [Reaction]
    var comments: [Comment]
}

@Model
class VoiceNote {
    var audioURL: URL                // Local; original audio kept on author's device only by default
    var transcript: String
    var duration: TimeInterval
    var processedAt: Date?
}

@Model
class Medication {
    var id: UUID
    var name: String
    var genericName: String?
    var dosage: String               // "10 mg"
    var form: String                 // "tablet"
    var schedule: MedicationSchedule
    var prescribingProvider: String?
    var pharmacy: Pharmacy?
    var notes: String?
    var startDate: Date
    var endDate: Date?
    var doseEvents: [DoseEvent]
}

@Model
class DoseEvent {
    var id: UUID
    var medication: Medication
    var scheduledAt: Date
    var takenAt: Date?
    var markedBy: Member?
    var status: DoseStatus           // .scheduled, .taken, .skipped, .missed, .late
}

@Model
class Appointment {
    var id: UUID
    var title: String
    var provider: String?
    var location: String?
    var startsAt: Date
    var duration: TimeInterval
    var attendees: [Member]
    var transportResponsible: Member?
    var prepNotes: String?
    var visitSummary: String?
}

@Model
class CareShift {
    var id: UUID
    var aide: Member
    var startsAt: Date
    var endsAt: Date
    var actualStart: Date?
    var actualEnd: Date?
    var services: [ServiceCategory]  // Maps to HCBS codes
    var notes: String?
    var milesDriven: Double?
}

@Model
class Document {
    var id: UUID
    var title: String
    var type: DocumentType           // .insuranceCard, .advanceDirective, .medList, .other
    var fileData: Data
    var fileMIMEType: String
    var createdAt: Date
    var sharedWith: [Member]
}
```

### 5.3 CloudKit schema and sharing model

- **Each Circle is backed by a CKShare** in the owner's private database.
- The owner is the Primary Caregiver who created the circle.
- All other members access the circle data via the shared database (`CKContainer.default().sharedCloudDatabase`).
- Records use a `CKRecordZone` named for the Circle UUID — keeps zones encapsulated and allows full deletion when a circle is closed.
- Sensitive document data (insurance cards, etc.) is **encrypted client-side** with a circle-symmetric key before being written to CloudKit. The key is itself stored in the iCloud Keychain, shared automatically across the owner's devices, and propagated to members via CKShare invitation flow.

**Why this matters:** CloudKit's at-rest encryption is good, but Apple holds the keys for unencrypted fields. By doing client-side encryption on the genuinely sensitive stuff, you can confidently say "no one outside the circle can see this content, including us."

### 5.4 AI / ML architecture

**On-device first, cloud as fallback.**

1. **Speech-to-text**: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`. Available on iPhone 11 and later in English. Fall back to server-side recognition for older devices, but log this to the user.

2. **Entity extraction and tagging**: iOS 26 Foundation Models framework with a structured-output prompt:
   ```
   System: You extract structured information from caregiver voice notes about an elderly family member. Return only valid JSON matching the schema. Never invent information.

   User: {transcript}

   Schema:
   {
     "vitals": [{"type": "BP|HR|temp|glucose|weight|spO2", "value": "string", "time": "ISO8601?"}],
     "symptoms": [{"description": "string", "severity": "mild|moderate|severe", "bodyPart": "string?"}],
     "meals": [{"description": "string", "time": "ISO8601?"}],
     "meds_taken": [{"name": "string", "time": "ISO8601?"}],
     "appointments_mentioned": [{"who": "string", "when": "ISO8601?"}],
     "mood": "string?",
     "concerns": ["string"],
     "summary": "string (one sentence)"
   }
   ```

3. **Daily digest**: Same framework, given the last 24h of activity entries, produce a 2-sentence summary. Generated on the Primary Caregiver's device only, then synced.

4. **Cloud fallback**: For users on devices that don't support Foundation Models, route through OpenAI gpt-4o-mini via a thin proxy (you need a tiny backend just for this). PHI is **always stripped** before sending — names of the care recipient are replaced with `[RECIPIENT]` and known caregiver names with `[CAREGIVER_N]`.

### 5.5 Notifications

| Trigger | Recipient(s) | Channel | Style |
|---|---|---|---|
| Missed med after grace period | Care Recipient, then Primary Caregiver after 15 min | Push, then Critical Alert if escalated | Standard, then Critical |
| Aide arrived / left (geofence) | Primary Caregiver, Family Members per pref | Push silent | Quiet |
| New voice note posted | Configurable per member | Push | Standard |
| Activity reaction or comment | Author of activity | Push | Quiet |
| SOS triggered | All members | Push + Critical Alert + CallKit ring | Critical |
| Appointment in 24h | Attendees + transport-responsible member | Push | Standard |
| Document expiring (insurance card date) | Primary Caregiver | Push | Standard |
| Weekly care minutes summary | Paid Family Caregiver, Primary Caregiver | Push | Quiet |

**Critical alerts** require Apple approval but are appropriate here for SOS and missed critical meds (e.g. insulin). Apply for the entitlement before submission.

### 5.6 Security and compliance

This is critical. Read this section twice.

- **HIPAA**: CareCircle in v1 is **NOT a HIPAA covered entity** and is **NOT a business associate of any provider**. It is a personal-use family tool. The user controls all data. The privacy policy and ToS must make this explicit. **Do not market the app as HIPAA-compliant.** If a future B2B path with home-care agencies opens, you'll need a BAA with Apple/CloudKit (which Apple offers for healthcare apps as of 2023) and a full HIPAA security review.
- **HITRUST / SOC 2**: Out of scope for v1.
- **GDPR / CCPA**: Yes, comply. Specifically: provide data export, full deletion, and a clear privacy policy with categories of data collected.
- **App Store category**: Medical or Health & Fitness. Medical is appropriate because of medication tracking; expect stricter review.
- **Required App Review responses**: Be prepared to answer Apple's Health & Fitness/Medical questions about FDA classification (the app is not a medical device; it's a record-keeping tool — emphasize this).
- **In-app disclaimers**: Every screen that shows medication info needs a small "Not medical advice — consult your healthcare provider" footer.
- **Data minimization**: Don't collect anything you don't need. Specifically: no advertising IDs, no third-party trackers, no fingerprinting.
- **Encryption**:
  - Data at rest: file protection class `.completeUntilFirstUserAuthentication` for SwiftData store; `.complete` for the document vault.
  - Sensitive fields: client-side AES-256-GCM via CryptoKit before CloudKit write.
  - In transit: TLS 1.3 only.
- **Audit log**: Maintain an immutable log of who-did-what-when on the circle's data, accessible to the Primary Caregiver. This is good practice and also matches what state self-direction programs increasingly require.
- **Children**: The app is not intended for users under 13. Set the App Store age rating accordingly.

### 5.7 Telemetry and privacy-respecting analytics

Track:

- Funnel events: launched, signed in, created circle, sent first invite, accepted invite, posted first activity, marked first med, recorded first voice note
- Feature usage: per-feature daily/weekly active rates
- Crash and ANR rates
- Subscription events via RevenueCat

Do **not** track:

- Any content of activities, voice notes, or messages
- Specific medications
- Care Recipient identifiers
- Member relationships

---

## 6. Monetization

### 6.1 Pricing tiers

| Tier | Price | What's included | Target |
|---|---|---|---|
| **Care Circle Basic** | Free | Up to 3 members, 1 medication, 1 document, activity feed, voice notes (cloud fallback transcription) | Trial / single caregivers |
| **Care Circle Family** | $12.99/mo or $99.99/yr | Up to 8 members, unlimited meds and docs, full features, on-device AI | Primary persona (Sarah) |
| **Care Circle Pro** | $24.99/mo or $199.99/yr | Everything in Family + care minutes log, weekly export, multi-circle, audit log, priority support | Paid family caregivers (Brenda persona) |

- **The Care Recipient never pays.** They are always free.
- **A 14-day free trial of Family or Pro** is available; no credit card required if signing in with Apple (use StoreKit's intro offer).
- **Family plan** is the headline tier and the assumed default — anchor visually around it.

### 6.2 Why this works

- **Per-circle pricing**, not per-user — easier to communicate ("$13/month covers your whole family").
- **The Pro tier monetizes a specific, high-pain, high-willingness-to-pay segment** (paid family caregivers) without requiring extra build cost — just expose existing features behind the paywall.
- **Annual discount** drives commitment (and reduces churn) — 36% effective discount on annual matches industry norms.

### 6.3 Avoid these monetization mistakes

- Don't try to charge the senior. Ever.
- Don't show ads. This category does not tolerate them and your trust evaporates.
- Don't sell aggregated/anonymized data. Even framed well, this kills the trust positioning.
- Don't gate emergency features (SOS, missed-med alerts) behind paywalls. Apple will reject.

---

## 7. Go-to-market

### 7.1 Initial wedge

Don't try to launch to "all caregivers." Launch to **one specific, reachable niche** where the app's unique strengths matter most.

**Recommended initial wedge: Sandwich-generation adult daughters in the US Midwest who are coordinating care for a parent with a recent diagnosis (heart failure, dementia, post-stroke, post-hip-fracture).**

Why this niche:
- High emotional pain → high willingness to pay
- The "recent diagnosis" moment is a habit-formation window
- Geographically targetable (Facebook, hospital discharge programs, social workers)
- Justin is in Minnesota — local network effects available

### 7.2 Launch channels (in order of effort vs. expected return)

1. **App Store SEO** — keywords: "family caregiver," "elderly parent," "medication tracker family," "care coordination," "Medicaid caregiver."
2. **Reddit** — r/AgingParents (200K+ subs), r/CaregiverSupport, r/dementia. Be a helpful contributor for 3 months before promoting.
3. **Facebook groups** — caregiver support groups (millions of users across them). Same rule: contribute first.
4. **Hospital discharge social workers** — visit 5–10 local hospitals, offer a free Pro account to their team in exchange for them mentioning the app to patients' families.
5. **State self-direction program advocacy organizations** — they have email lists of paid family caregivers.
6. **Content marketing** — "How to track your hours for [state] Medicaid self-direction" guides. SEO play with clear product mention.
7. **TikTok / Instagram Reels** — show real daughter-mom moments, never preachy.

### 7.3 Success metrics

**North Star metric**: weekly active circles with 3+ engaged members.

| Metric | 90-day target | 12-month target |
|---|---|---|
| App Store rating | 4.5+ | 4.7+ |
| Total installs | 5,000 | 50,000 |
| Active circles | 800 | 8,000 |
| Paid conversion (free → paid) | 6% | 9% |
| Annual subscriber retention | n/a | 75%+ |
| MRR | $5K | $50K |
| Reviews mentioning "sibling" or "family" | 30%+ | 30%+ |

---

## 8. Development plan and milestones

### 8.1 Phasing — 12-week MVP

**Weeks 1–2: Foundation**
- Project setup, SwiftData schema, CloudKit zone setup
- Sign in with Apple + Apple Push entitlements
- Empty-state Home, Today, Meds, More tabs
- Circle creation and basic profile

**Weeks 3–4: Sharing and members**
- CKShare-based invitations
- Member roles and permissions enforcement
- Activity feed (text and photos only at this stage)
- Push notifications via CKSubscription

**Weeks 5–6: Voice handoff**
- Speech framework integration
- Entity extraction (Foundation Models or cloud fallback)
- Tag system and feed display
- Daily digest scaffolding

**Weeks 7–8: Medications**
- Med data model and scheduling
- Scan-label flow with VisionKit
- Reminders and Live Activity
- Missed-dose escalation logic
- openFDA interaction warnings

**Week 9: Documents and calendar**
- Document vault with encryption
- Appointment calendar with EventKit sync
- Provider visit prep view

**Week 10: SOS and care minutes**
- SOS flow with location sharing and CallKit
- Care minutes log + PDF export
- Geofence detection for aide shifts (optional toggle)

**Week 11: Polish, accessibility, onboarding**
- Onboarding flow finalization
- VoiceOver pass, Dynamic Type pass, color contrast pass
- Settings, account management, data export, deletion
- Care Recipient simplified mode

**Week 12: TestFlight beta and submission**
- Internal TestFlight (5 testers)
- External TestFlight (100 testers via caregiver communities)
- Crash and feedback triage
- App Store submission with Critical Alert entitlement requested in parallel

### 8.2 Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Apple rejects for medical positioning | Medium | High | Position as "record keeping," not "medical device"; have appeals prepared with examples of approved apps in same space (Medisafe, CareZone) |
| CloudKit sharing flow has UX edge cases (especially invites to non-iCloud users) | High | Medium | Test extensively early in week 3–4; build a magic-link web fallback that prompts to install if recipient isn't on iCloud |
| On-device LLM unavailable on enough devices to matter | Medium | Medium | Cloud fallback proxy ready; PHI-stripping pipeline tested |
| Speech recognition accuracy varies for elderly voices and regional accents | Medium | Medium | Manual edit affordance always available; consider Whisper API for low-confidence segments |
| State self-direction programs change their documentation requirements | Low | Medium | Care minutes export is intentionally "ready to edit" rather than "auto-submit"; reduces blast radius |
| Critical Alert entitlement denied | Medium | Low | Fall back to time-sensitive notifications; the feature still works |
| Competitor adds voice handoff first | Medium | Medium | Speed to market matters; voice + sibling-coordination + paid-caregiver-docs is a defensible *combination* |
| HIPAA scope creep from B2B inbound interest | Low | High | Stay personal-tool-only in v1; B2B is v3 with proper compliance |

---

## 9. Open questions / decisions deferred

These don't block v1, but should be revisited.

1. **Pricing experiment** — should we test $9.99/mo for Family? Hold for 90 days post-launch.
2. **iPad app** — supported but not optimized in v1. Caregivers do use iPads. Worth a v2 optimization pass.
3. **Apple Watch app for Care Recipient** — likely powerful (fall detection relay, med reminders, big-button SOS). Plan for v2.
4. **Multi-language support** — Spanish first, given US caregiver demographics. v2.
5. **Family Sharing integration** — could discount the app inside an Apple Family. Apple's mechanics here are good. Investigate for v2.
6. **Care Recipient owns the data legally — what happens when they pass away?** Need explicit handling. Recommend: data is preserved for 90 days, then Primary Caregiver chooses to archive (download ZIP) or delete.

---

## 10. Appendices

### Appendix A: Full SwiftData model — see `/Models/` folder once project is initialized

### Appendix B: Required API keys, accounts, services

| Service | Purpose | Cost in v1 |
|---|---|---|
| Apple Developer Program | App distribution | $99/yr |
| Apple Push (Critical Alerts entitlement) | Critical med and SOS alerts | Apply via developer.apple.com |
| OpenAI API (fallback only) | LLM tagging on older devices | ~$10/mo at MVP scale |
| openFDA | Drug interactions | Free |
| RevenueCat | Subscription management | Free under $2.5K MTR |
| TelemetryDeck or PostHog | Analytics | $0–$50/mo |
| Sentry | Crash reporting | Free tier |
| Domain | carecircle.app (verify availability) | $15/yr |
| Squarespace or Framer | Marketing site | $20/mo |

### Appendix C: 🤖 Agent-ready scopes

For handoff to Claude Code or another coding agent, each of the following is a self-contained spec that can be implemented as a single prompt:

**Scope C1: Project bootstrap**
> Create an iOS 18+ SwiftUI app called CareCircle with: a 4-tab TabView (Home, Today, Meds, More); SwiftData container with the entities defined in this spec's section 5.2; Sign in with Apple authentication; CloudKit container `iCloud.app.carecircle` with private and shared databases; basic empty-state views for each tab; a debug-only "seed data" button on More that populates a sample Circle. Use SF Symbols for tab icons. Apply a sage-green tint color via `.tint(.sage)` extending Color with `sage = Color(red: 0.45, green: 0.6, blue: 0.5)`.

**Scope C2: Circle creation and CKShare invitations**
> In the CareCircle app, build the circle creation flow per spec section 4.2 onboarding steps 1–5, and the CKShare-based invite flow that supports sending via share sheet (Messages, Mail). Handle the participant acceptance flow when the recipient opens a `cloudkit:` URL. Show pending invites in More > Circle Members. Enforce the 8-member maximum and the role permissions matrix from section 2.3.

**Scope C3: Voice handoff with on-device transcription**
> Build the voice handoff feature per section 4.3. Use AVAudioRecorder for recording (m4a, 64kbps), SFSpeechRecognizer with on-device mode, auto-stop after 4 seconds silence using AVAudioEngine's audio level metering. Display a real-time waveform during recording using Canvas. After stop, transcribe and display the transcript in an editable TextEditor with extracted entities highlighted using AttributedString. Post the result as an Activity record to the Circle's CKRecordZone.

(And so on for each remaining feature.)

### Appendix D: Glossary

- **HCBS** — Home and Community-Based Services (Medicaid)
- **CDPAP** — Consumer Directed Personal Assistance Program (NY)
- **FI** — Fiscal Intermediary (the agency that processes payroll for paid family caregivers)
- **PPL** — Public Partnerships LLC, the dominant fiscal intermediary
- **Section 1915(c)** — The Medicaid waiver authority most often used for self-directed services
- **CKShare** — CloudKit's mechanism for sharing data between iCloud users
- **SiwA** — Sign in with Apple
- **Critical Alert** — An Apple Push notification class that bypasses Do Not Disturb; requires entitlement

---

*End of CareCircle product specification, v1.0.*
