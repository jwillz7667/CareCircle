export const meta = {
  name: 'appstore-readiness-audit',
  description: 'Audit CareCircle iOS for App Store submission readiness + feature functionality, verify findings, synthesize a prioritized fix plan',
  phases: [
    { title: 'Audit', detail: '11 parallel auditors across readiness + feature dimensions' },
    { title: 'Verify', detail: 'adversarially confirm each finding against the code' },
    { title: 'Synthesize', detail: 'prioritized fix plan: blockers, fixable-now, requires-user' },
  ],
}

const CONTEXT = `
PROJECT: CareCircle — iOS family-caregiving app. SwiftUI + SwiftData + CloudKit, Swift 6 with project-wide MainActor isolation (SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor). Repo root: /Users/willz/ai/CareCircle. App sources under CareCircle/Sources/ (App/, Features/<Domain>/, Core/, Services/, Models/, DesignSystem/). There is ALSO a Node/Fastify backend under backend/ but THIS AUDIT IS iOS-ONLY unless a finding is iOS-blocking.

GOAL OF THIS AUDIT: determine what is needed to (a) submit this app to the App Store and (b) ensure every shipped feature is actually functional/reachable. Output concrete, real, file-cited findings only — no speculation, no generic advice.

ALREADY-KNOWN FACTS (do NOT re-report these as discoveries; build on them):
- xcodebuild build SUCCEEDS for the iOS Simulator.
- IPHONEOS_DEPLOYMENT_TARGET=17.0; MARKETING_VERSION=1.0; CURRENT_PROJECT_VERSION=1; DEVELOPMENT_TEAM=487LC4H9U4; CODE_SIGN_STYLE=Automatic; bundle id Res.CareCircle; TARGETED_DEVICE_FAMILY=1,2 (iPhone AND iPad).
- NO PrivacyInfo.xcprivacy privacy manifest exists anywhere in the repo.
- Entitlements (CareCircle/CareCircle.entitlements) declare iCloud container "iCloud.com.jwillz.carecircle", but CLAUDE.md/spec say it should be "iCloud.Res.CareCircle". aps-environment=development. HealthKit + health-records, Sign in with Apple all present.
- UserDefaults is used in ~6 source files (a required-reason API for the privacy manifest).
- No print()/debugPrint, no hardcoded secrets, no #if DEBUG blocks in sources.
- swiftformat --lint fails on 10 files (mostly BackendHydrator.swift wrap rules); swiftlint reports 33 violations, mostly length (one error-level: SyncEngine.swift type_body_length).
- The tab bar is [Today][Meds][Brain][More] (CareCircle/Sources/App/MainTabView.swift, AppTab.swift).

IMPORTANT — AVOID RE-REPORTING RESOLVED WORK: First read docs/AUDIT_2026-06-01_RESOLUTION.md and docs/FEATURE_AUDIT.md. A prior audit already FIXED a large list (sync dead-letter, SOS fanout, APNs registration, RLS, StoreKit idempotency, PHI redaction, account deletion/export, schema versioning, location consent per-circle, Reduce Motion, Dynamic Type sub-13pt, MetricKit telemetry, etc.) and DEFERRED some by design (missed-dose escalation chain, inbound merge stub, ThisDeviceOnly doc keys, design-token migration, light-mode pin, real DDI checking, i18n). Do NOT report already-fixed items as new. You MAY report a deferred item only if it is an actual App Store SUBMISSION BLOCKER (most are not).

PROJECT RULES (violations are findings): no force-unwrap (!) in production code (test code ok); no singletons in production paths (inject via init or SwiftUI Environment); every medication-related screen must show a "Not medical advice — consult your healthcare provider" footer; accessibility mandatory (Dynamic Type to AX5, VoiceOver labels on interactive elements, 4.5:1 contrast, 44x44pt targets, Reduce Motion); SF Symbols only for icons in v1; the Care Recipient never pays; never market as HIPAA-compliant.

FINDING QUALITY BAR: each finding must name a real file (path) and ideally a line, quote concrete evidence, set an honest severity, and a precise category. Severity: blocker = cannot submit / app broken; high = should fix before submit; medium = quality gap; low = nice-to-have. Category MUST be one of: ios-fixable-now (a code/manifest/asset edit Claude can make from the filesystem), requires-xcode-ui (needs project.pbxproj / capabilities / target creation / signing in Xcode UI — Claude is FORBIDDEN from editing project.pbxproj), requires-decision (a product/business decision the user must make), backend (server-side), doc-only (documentation drift). Prefer FEWER, HIGH-CONFIDENCE findings over a long speculative list.
`

const FINDING_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    dimension: { type: 'string' },
    summary: { type: 'string', description: 'one-paragraph state-of-this-dimension' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['blocker', 'high', 'medium', 'low'] },
          category: { type: 'string', enum: ['ios-fixable-now', 'requires-xcode-ui', 'requires-decision', 'backend', 'doc-only'] },
          files: { type: 'array', items: { type: 'string' } },
          evidence: { type: 'string' },
          recommendation: { type: 'string' },
        },
        required: ['title', 'severity', 'category', 'files', 'evidence', 'recommendation'],
      },
    },
  },
  required: ['dimension', 'summary', 'findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    confirmed: { type: 'boolean', description: 'true if the finding reproduces against the actual code' },
    adjustedSeverity: { type: 'string', enum: ['blocker', 'high', 'medium', 'low', 'not-an-issue'] },
    note: { type: 'string', description: 'what you found when you read the cited files; correct any inaccuracy' },
  },
  required: ['confirmed', 'adjustedSeverity', 'note'],
}

const DIMENSIONS = [
  {
    key: 'R1-privacy-permissions',
    prompt: `Dimension: PRIVACY MANIFEST & PERMISSIONS.
Determine exactly what an App Store submission requires here.
1. Privacy manifest (PrivacyInfo.xcprivacy): it does not exist. Enumerate what it MUST contain for THIS app: (a) NSPrivacyAccessedAPITypes with reason codes — search Sources for every required-reason API actually used (UserDefaults [CA92.1], file timestamp APIs, system boot time/uptime, disk space, active keyboard). (b) NSPrivacyCollectedDataTypes — derive the real list from what the app collects (health, contact name/email/phone, precise/coarse location, audio, photos, user content, user id, crash data via MetricKit). (c) NSPrivacyTracking=false, NSPrivacyTrackingDomains=[]. Cross-check against docs/TESTFLIGHT_PREP.md section 4. Produce a single finding describing the required manifest content (category ios-fixable-now).
2. Info.plist usage strings: read CareCircle/Info.plist. For EVERY permission the code actually requests, confirm a usage string exists. Search the code for the request sites: AVCaptureDevice/camera, AVAudioSession/microphone record, SFSpeechRecognizer, CLLocationManager (when-in-use AND always), EKEventStore/calendar, HKHealthStore, PHPicker/photo library, CNContactStore/contacts, UNUserNotificationCenter, LAContext/FaceID/biometrics. Any requested permission MISSING its Info.plist string is a blocker. Any usage string present for a permission NEVER requested is dead (low).
Report findings per the schema.`,
  },
  {
    key: 'R2-entitlements-buildsettings',
    prompt: `Dimension: ENTITLEMENTS / CAPABILITIES / SIGNING / BUILD SETTINGS.
Read CareCircle/CareCircle.entitlements, CareCircle/Info.plist, and CLAUDE.md.
1. iCloud container mismatch: entitlements declare "iCloud.com.jwillz.carecircle" but CLAUDE.md/spec reference "iCloud.Res.CareCircle". Determine which the CODE expects — grep Sources for CKContainer(identifier:) and any container literal. Flag the mismatch and which value is authoritative; this affects whether CloudKit works in production. (Likely requires-xcode-ui or requires-decision.)
2. aps-environment=development → for an App Store / TestFlight build this should be production. Explain the correct handling (Xcode automatic signing vs explicit value) and whether it is a submission blocker.
3. TARGETED_DEVICE_FAMILY=1,2 means the app advertises iPad support. Search for any iPad-specific layout/size-class handling. If there is none, shipping as universal means reviewers test on iPad and may reject for broken layout. Flag the decision: restrict to iPhone (family 1) or commit to iPad. (requires-xcode-ui / requires-decision.)
4. Confirm capabilities used by code are all entitled: HealthKit (read sites), CloudKit, Sign in with Apple, Push. Note Critical Alerts entitlement status (pending Apple) and that code must already fall back — verify the fallback exists.
5. Version/build: 1.0 / 1 is fine for first submission — only flag if something references a different value.
Report findings per the schema.`,
  },
  {
    key: 'R3-storekit-paywall',
    prompt: `Dimension: STOREKIT / PAYWALL / SUBSCRIPTIONS (App Store guideline 3.1.x compliance).
Read CareCircle/CareCircle.storekit and everything under CareCircle/Sources/Features/Paywall/ and CareCircle/Sources/Services/Subscriptions/.
1. Product IDs: do the product identifiers in the .storekit config exactly match the IDs the code purchases/queries? Mismatch = paywall shows nothing in production (blocker).
2. Purchase flow completeness: is there a working purchase path, a Restore Purchases control (required by Apple), and transaction verification (StoreKit 2 Transaction.currentEntitlements / verificationResult)?
3. Required paywall UI per App Store Review 3.1.2: subscription length, price, links to Terms of Use (EULA) and Privacy Policy must be visible on the paywall. Check the Paywall views for these.
4. The Care Recipient must never be charged (project rule) — verify the paywall is only presented to the paying caregiver role, not the recipient.
5. Server-side entitlement enforcement exists per the prior audit — confirm the iOS side reflects entitlement state and gates premium features. Identify which features are gated and whether free users hit a sensible wall vs a broken screen.
Report findings per the schema.`,
  },
  {
    key: 'R4-assets-footers-meta',
    prompt: `Dimension: ASSETS / LAUNCH / MEDICAL FOOTERS / METADATA-IN-APP.
1. App icon: read CareCircle/Assets.xcassets/AppIcon.appiconset/Contents.json — it uses a single 1024 universal icon plus dark+tinted variants (the modern iOS single-size icon). Confirm this is valid for submission (it is, for iOS 17+). Only flag a real problem (e.g. missing the default/any-appearance entry, or alpha channel in the PNG which Apple rejects). Inspect the PNGs' alpha if possible.
2. Launch screen: is there a LaunchScreen / UILaunchScreen config? Search Info.plist and assets. Missing launch screen on modern targets uses a default — flag only if there is an explicit broken reference.
3. AccentColor + any referenced colors/images: scan for asset references in code (Image("..."), Color("...")) that have NO matching entry in Assets.xcassets — those render blank in production (high).
4. Medical-advice footer rule: EVERY medication-related screen must show "Not medical advice — consult your healthcare provider". Enumerate medication-related screens under Features/Meds, Features/Pulse (med insights), Features/Appointments (if med-related), and verify each shows the footer. List any missing it (high — explicit project rule).
5. SF Symbols only (v1 rule): scan Image(...) usages for any non-SF-Symbol raster image used as an icon (other than the app logo). Flag custom raster icons.
Report findings per the schema.`,
  },
  {
    key: 'R5-code-hygiene-release',
    prompt: `Dimension: RELEASE CODE HYGIENE & CORRECTNESS.
1. Force-unwraps in production (project rule #3 forbids them): grep Sources for force-unwrap patterns ("!" used as force-unwrap, "as!", "try!"). Distinguish genuine force-unwraps from legitimate "!" (logical-not, non-optional). Report any real force-unwrap in production code with file:line.
2. fatalError/preconditionFailure: there are known ones in CareCircleApp.swift (ModelContainer init), GoogleSignInCoordinator/SignInView (SecRandomCopyBytes), OpenFDAClient (hardcoded URL), BackendConfiguration (prod URL). Judge each: is it a genuinely-impossible state (acceptable) or a reachable crash (blocker)? A ModelContainer that fails to init on a user device WILL crash the app on launch — assess whether a recoverable path is warranted.
3. Singletons in production (rule #4): grep for "static let shared" / "static var shared" in Sources; the prior audit removed some — confirm none remain in production paths.
4. swiftformat + swiftlint: 10 files fail swiftformat --lint and there are 33 swiftlint violations incl one error-level (SyncEngine type_body_length). These are CI-failing/style. Summarize as one finding (ios-fixable-now) noting they don't affect runtime but should be clean before tagging a release.
5. Error handling at boundaries: spot-check the network layer (Services/Backend/APIClient.swift) and any place that decodes external JSON — are failures typed and surfaced, or silently swallowed in a way that would show a blank screen to a user? Report only concrete swallow-and-blank cases.
6. Any leftover developer/test affordances reachable in a release build (debug menus, seed-data buttons, hardcoded test logins). Check docs/SEED_LOGINS.md context and grep for seed/debug UI.
Report findings per the schema.`,
  },
  {
    key: 'F1-navigation-orphans',
    prompt: `Dimension: NAVIGATION REACHABILITY & ORPHANED FEATURES.
The shipped tab bar is [Today][Meds][Brain][More] (CareCircle/Sources/App/MainTabView.swift). FEATURE_AUDIT.md says several folders were to be folded or killed: Insights→fold into Pulse/Today, Journal→fold into Brain, Activity→becomes Brain feed, Home→replaced by HomeDashboardView, Today→a component, SimplifiedMode→kill pending evidence, Vitals/Location/Shifts/CareMinutes→demoted into More.
TASK: For EVERY folder under CareCircle/Sources/Features/ (Activity, Appointments, Auth, Brain, CareMinutes, Circle, Documents, EmergencyContacts, HealthRecords, Home, Insights, Journal, Location, Meds, Members, More, Paywall, Pulse, Shifts, SimplifiedMode, SOS, Today, Vitals), determine whether its primary view(s) are actually REACHABLE in the running app — i.e. referenced (transitively) from MainTabView / HomeDashboardView / BrainView / MedsView / MoreView or a NavigationLink/sheet/fullScreenCover from a reachable view. Use grep to find references to each feature's main View type.
Classify each feature: REACHABLE (and from where), ORPHANED (compiles but no entry point — dead code), or DEAD-FILE (not referenced at all). Orphaned features are not submission blockers but are findings (medium) because "ensure all features functional" requires either wiring them or deleting them. Also flag any reachable navigation that dead-ends (a "See all"/button that goes nowhere or to an empty view). Read MoreView to confirm what it actually surfaces vs FEATURE_AUDIT's intended More contents.
Report findings per the schema: one finding per orphaned/dead feature or broken nav link; put the full reachability classification in the summary.`,
  },
  {
    key: 'F2-auth-circle-members',
    prompt: `Dimension: CORE ONBOARDING — AUTH, CIRCLE, MEMBERS.
Trace these flows end to end in CareCircle/Sources/Features/Auth, Features/Circle, Features/Members, Features/Onboarding (if any), and the App/ root views (RootView, SignedInRootView, SignInView).
1. Three sign-in paths must work: Sign in with Apple, Sign in with Google, email+password. For EACH: is the UI button present, wired to a coordinator/service, and does success route into the signed-in root? Note: a memory says Google sign-in needs two Info.plist keys added in Xcode UI before the button shows — verify whether the Google button is conditionally hidden and whether the required GoogleOAuthClientId / URL scheme are present in Info.plist (they ARE in Info.plist per earlier scan). Determine if Google sign-in is actually functional or still gated.
2. First-run: with no signed-in user, does SignInView show and complete? After sign-in with no circle, is there an empty-state / circle-creation path?
3. Circle creation + CloudKit share (CKShare) invite flow: trace create-circle → add care recipient → invite member. Flag any incomplete/stubbed step (CKShare simulator caveat is known/acceptable; only flag genuine code gaps).
4. Member roles & permissions: owner/caregiver/recipient roles, the PATCH-members owner-guard (prior audit fixed second-owner). Confirm role gating in the UI.
Report concrete findings only.`,
  },
  {
    key: 'F3-meds-wedgeB',
    prompt: `Dimension: MEDS (Wedge B — medication safety). Trace CareCircle/Sources/Features/Meds and CareCircle/Sources/Services/Medications.
Verify each capability is actually implemented and wired (not a stub):
1. Add/edit/delete medication; schedule entry; dose state transitions (taken/skipped/missed).
2. Label scanner (camera) → OpenFDA enrichment (OpenFDAClient): does scanning produce a parsed result and populate the med? Is there a graceful path when OpenFDA returns nothing/offline?
3. Reminders: local notification scheduling within the 64-request ceiling (prior audit bounded this), interruption level, sound. Confirm reminders are scheduled on med create and rescheduled on edit.
4. Interaction checking: the InteractionChecker honestly scopes to same-ingredient duplication only (real DDI is backlog). Verify the UI disclaims this and does not imply real interaction safety.
5. Adherence/refills: is adherence computed from real dose records? Are refills tracked or stubbed?
6. "Not medical advice" footer present on med screens.
7. The known TODO in SOSCenter about critical-alert entitlement — not a meds blocker, skip unless it affects missed-dose escalation here.
Report concrete findings: anything stubbed, unwired, or user-facing-broken.`,
  },
  {
    key: 'F4-pulse-wedgeE',
    prompt: `Dimension: PULSE / TODAY / INSIGHTS (Wedge E — on-device intelligence). Trace CareCircle/Sources/Features/Pulse, Features/Today, Features/Insights, Features/Home (HomeDashboardView), and Services/Insights, Services/Extraction.
1. On-device AI: spec says Foundation Models on iOS 26+, with a PHI-stripped cloud fallback for older devices. Since deployment target is now 17.0, the MAJORITY of users will be on <26 → the fallback path is the primary path. Verify: (a) is there an availability check for FoundationModels / the on-device model? (b) does a cloud fallback actually exist and is it wired, or does intelligence silently do nothing on iOS 17–25? (c) before anything leaves the device, are Care Recipient/caregiver names replaced with [RECIPIENT]/[CAREGIVER_N] (PHIRedactor)? This is the single most important Wedge-E correctness question — if on-device-only and gated to iOS 26, then on a 17.0 floor the headline feature is dead for most users. Assess carefully and report severity honestly.
2. HomeDashboardView (Today tab): does it actually render headline insight + today's meds/appointments, or are sections empty/stubbed? Does it degrade gracefully with no data (empty states)?
3. Confidence thresholds: insights claim conservative thresholds — verify low-confidence insights are suppressed, not shown as fact.
4. Appointment prep/debrief generation (Pulse companion) — implemented or stub?
Report concrete findings, especially the iOS-version availability gap for the AI path.`,
  },
  {
    key: 'F5-brain-wedgeA',
    prompt: `Dimension: BRAIN / ACTIVITY / JOURNAL / DOCUMENTS (Wedge A — shared record). Trace CareCircle/Sources/Features/Brain, Features/Activity, Features/Journal, Features/Documents, and Services/Documents.
1. BrainView is a single file — confirm what it renders. FEATURE_AUDIT says it reuses ActivityFeedView as the feed. Verify the Brain tab actually shows a working feed (posts load, compose works) and is not an empty shell.
2. Activity feed: post text/photo/voice activity; does it persist (SwiftData) and sync (CloudKit)? Comments paginated (prior audit). Any compose path that dead-ends?
3. Journal: FEATURE_AUDIT says fold into Brain as a note template. Is Journal still a separate reachable surface, orphaned, or actually integrated?
4. Documents: E2EE document upload/view (AES-GCM, per-circle key). Trace add-document → encrypt → store → view/decrypt. Is the full round trip implemented, or is viewing/decrypt stubbed? Confirm the "narrow" ER-brief doc set works.
5. ER-brief / decision-history generator mentioned in the wedge — implemented or absent? If absent but advertised in UI, that's a finding.
Report concrete findings only.`,
  },
  {
    key: 'F6-safety-secondary',
    prompt: `Dimension: SAFETY & SECONDARY FEATURES. Trace SOS, Location, EmergencyContacts, Shifts, CareMinutes, Vitals, HealthRecords, Appointments (Features/* and matching Services/*).
1. SOS: countdown UI, location capture on arm (prior audit fixed the auth race), backend fanout (prior audit), tel:// dial of primary contact, cancel/resolve. Verify the full path is wired and the critical-alert TODO has a working time-sensitive fallback.
2. Location: per-circle consent (prior audit), map surface, background updates gated on consent. Confirm the single Location view is reachable from More and functions.
3. EmergencyContacts: add/list contacts feeding SOS + ER brief. Reachable + persists?
4. Shifts + CareMinutes: secondary surfaces in More. Reachable and functional (who's-on-duty strip in Today; care-load ring)? CareMinutes PDF export — works or stub (the e-signature gap is known/acceptable)?
5. Vitals: HealthKit reader (returns empty on simulator — acceptable), analytics, history archive in More. Reachable and renders with seeded data?
6. HealthRecords: Apple Health clinical-records import. Single file — confirm it's wired and the entitlement matches.
7. Appointments: create appointment, mirror to iOS Calendar (EventKit), prep/debrief link to Pulse. Calendar permission string present. Verify mirror actually writes an EKEvent.
Report concrete findings: anything stubbed, unreachable, or broken.`,
  },
]

phase('Audit')

// pipeline: each dimension is found, then each of its findings is adversarially verified.
const perDimension = await pipeline(
  DIMENSIONS,
  (d) => agent(`${CONTEXT}\n\n=== YOUR ASSIGNMENT ===\n${d.prompt}`, {
    label: `audit:${d.key}`,
    phase: 'Audit',
    schema: FINDING_SCHEMA,
  }),
  (result, d) => {
    if (!result || !result.findings || result.findings.length === 0) {
      return { dimension: d.key, summary: result ? result.summary : 'no result', findings: [] }
    }
    return parallel(
      result.findings.map((f) => () =>
        agent(
          `${CONTEXT}\n\n=== ADVERSARIAL VERIFICATION ===\nAnother auditor reported this finding for the CareCircle iOS app. Independently verify it by READING the cited files (and grepping if needed). Confirm only if it genuinely reproduces. If the finding is inaccurate, already-handled, or not actually a submission/functionality problem, mark confirmed=false and adjustedSeverity=not-an-issue and explain. If real but mis-rated, set the correct severity. Be skeptical; default to demoting vague findings.\n\nFINDING:\n- dimension: ${d.key}\n- title: ${f.title}\n- severity(claimed): ${f.severity}\n- category: ${f.category}\n- files: ${(f.files || []).join(', ')}\n- evidence: ${f.evidence}\n- recommendation: ${f.recommendation}`,
          { label: `verify:${d.key}:${(f.title || '').slice(0, 28)}`, phase: 'Verify', schema: VERDICT_SCHEMA },
        ).then((v) => ({ ...f, dimension: d.key, verdict: v })),
      ),
    ).then((verified) => ({ dimension: d.key, summary: result.summary, findings: verified.filter(Boolean) }))
  },
)

// flatten verified findings; keep only confirmed, real ones
const allFindings = perDimension
  .filter(Boolean)
  .flatMap((r) => (r.findings || []))
  .filter((f) => f.verdict && f.verdict.confirmed && f.verdict.adjustedSeverity !== 'not-an-issue')
  .map((f) => ({
    title: f.title,
    dimension: f.dimension,
    severity: f.verdict.adjustedSeverity,
    category: f.category,
    files: f.files,
    evidence: f.evidence,
    recommendation: f.recommendation,
    verifyNote: f.verdict.note,
  }))

const dimSummaries = perDimension.filter(Boolean).map((r) => `- ${r.dimension}: ${r.summary}`).join('\n')

log(`Audit complete: ${allFindings.length} confirmed findings across ${perDimension.length} dimensions`)

phase('Synthesize')

const PLAN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  properties: {
    overallVerdict: { type: 'string', enum: ['ready', 'minor-gaps', 'not-ready'] },
    readinessSummary: { type: 'string', description: 'executive summary, 1-2 paragraphs' },
    reportMarkdown: { type: 'string', description: 'full prioritized report in GitHub-flavored markdown, grouped by Blockers / Fix-now (Claude) / Requires user (Xcode UI or decision) / Feature gaps / Polish. Include file paths and concrete actions.' },
    tasks: {
      type: 'array',
      description: 'deduped, prioritized, actionable task list',
      items: {
        type: 'object',
        additionalProperties: false,
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['blocker', 'high', 'medium', 'low'] },
          owner: { type: 'string', enum: ['claude', 'user'] },
          category: { type: 'string', enum: ['ios-fixable-now', 'requires-xcode-ui', 'requires-decision', 'backend', 'doc-only'] },
          files: { type: 'array', items: { type: 'string' } },
          action: { type: 'string', description: 'precise step to take' },
        },
        required: ['title', 'severity', 'owner', 'category', 'action'],
      },
    },
  },
  required: ['overallVerdict', 'readinessSummary', 'reportMarkdown', 'tasks'],
}

const plan = await agent(
  `${CONTEXT}\n\n=== SYNTHESIS ===\nYou are the lead engineer compiling the App Store readiness verdict for CareCircle iOS. Below are the per-dimension summaries and the full list of CONFIRMED, verified findings from 11 auditors. Deduplicate overlaps, resolve any conflicts, and produce a single prioritized plan.\n\nRules for the plan:\n- owner=claude for anything fixable from the filesystem (code, PrivacyInfo.xcprivacy, entitlements file edits, assets, docs, lint). owner=user ONLY for things that genuinely require the Xcode UI (project.pbxproj/build settings/capabilities/target creation/signing/archive) or a product/business DECISION.\n- Order tasks: blockers first, then high, then medium/low.\n- Be concrete: name files and the exact change.\n- Distinguish a true SUBMISSION BLOCKER (Apple will reject / app is broken) from quality work.\n- The privacy manifest is almost certainly a blocker (required for new submissions). The iPad-family and iCloud-container questions are likely decisions. Treat the iOS-version AI fallback gap (Wedge E on a 17.0 floor) with the seriousness it deserves.\n\nDIMENSION SUMMARIES:\n${dimSummaries}\n\nCONFIRMED FINDINGS (JSON):\n${JSON.stringify(allFindings, null, 2)}`,
  { label: 'synthesize:readiness-plan', phase: 'Synthesize', schema: PLAN_SCHEMA },
)

return { overallVerdict: plan.overallVerdict, readinessSummary: plan.readinessSummary, reportMarkdown: plan.reportMarkdown, tasks: plan.tasks, rawFindingCount: allFindings.length }
