# Phase 32 — Pill Identifier (NDC barcode + interaction checks)

## Goal

Let a caregiver scan the barcode on a pill bottle, look the medication up in
openFDA's NDC directory, surface its active ingredients and route, and warn
when those ingredients overlap with medications already in the active Circle.

Output stays advisory — the disclaimer rules from §3.1 #5 (CLAUDE.md) and
§5.6 (spec) still apply. The feature does NOT do real DDI (drug-drug
interaction) lookup; ingredient overlap is the v1 heuristic.

## Out of scope

- Real DDI database (RxNav, DrugBank, etc.). Too risky to ship in a
  record-keeping tool without a medical reviewer.
- Pill-image recognition (computer vision).
- OTC label scanning beyond what openFDA's `drug/ndc.json` supports.
- Backend mirror for the result. The scan is a stateless query; if the user
  adopts the medication, that flows through the existing AddMedication path
  which already mirrors to backend.

## Trigger surface

`MedicationListView` toolbar gains an "Identify pill" button next to the
existing "Add medication" pill. Tapping presents `PillIdentifierView` as a
sheet. The Phase 31 entry under More → Insights stays as-is.

## Files

New

- `CareCircle/Sources/Services/Medications/PillIdentificationResult.swift` —
  value type containing brand names, generic names, active ingredients, route,
  dosage form, NDC, and warning strings as surfaced by openFDA.
- `CareCircle/Sources/Services/Medications/UPCNormalizer.swift` — pure
  function `candidateNDCs(from: String) -> [String]` that maps a UPC-A
  payload to a ranked list of NDC candidate strings to query.
- `CareCircle/Sources/Services/Medications/PillIdentifier.swift` — actor that
  orchestrates the lookup: try each candidate NDC against
  `OpenFDAClient.lookup(ndc:)`, return the first hit, or nil.
- `CareCircle/Sources/Services/Medications/InteractionChecker.swift` —
  ingredient-overlap heuristic taking a `PillIdentificationResult` and the
  Circle's active medications, returning rows of "matched ingredient X with
  medication Y".
- `CareCircle/Sources/Features/Meds/PillIdentifierView.swift` — coordinator
  view managing scanner / result / error state.
- `CareCircle/Sources/Features/Meds/PillScannerView.swift` —
  `UIViewControllerRepresentable` over an AVCaptureSession metadata-output
  pipeline that detects EAN-13 / UPC-A / Code-39 / Code-128 barcodes (the
  formats commonly stamped on US pill bottles).
- `CareCircle/Sources/Features/Meds/PillIdentifierResultView.swift` — result
  display with brand/generic/ingredients/route, interaction-overlap rows, an
  "Add to medications" CTA that routes into `AddMedicationView` pre-filled,
  and the standard medical disclaimer footer.

Modified

- `CareCircle/Sources/Services/Medications/OpenFDAClient.swift` — add
  `lookup(ndc: String) async throws -> OpenFDANDCResult?` that hits
  `/drug/ndc.json`. Returns a new `OpenFDANDCResult` rather than reusing
  `OpenFDALabelResult` because the NDC endpoint carries route + dosage
  form + product_ndc fields the label endpoint doesn't.
- `CareCircle/Sources/Features/Meds/MedicationListView.swift` — toolbar
  button surfaces `PillIdentifierView`.
- `CareCircle/Sources/Features/Meds/MedicationDraft.swift` — convenience
  initializer that builds a draft from a `PillIdentificationResult` (so the
  "Add to medications" CTA pre-fills name, dosage form, fdaIngredients).
- `CareCircle/Sources/Features/Meds/AddMedicationView.swift` — accepts an
  `initialDraft: MedicationDraft?` parameter so the identifier flow can
  pre-fill the form.

## Implementation notes (post-build)

- `PillIdentifier` is a `Sendable` struct rather than an actor — its only
  state is the injected `OpenFDAClient`, and routing through an actor would
  add a hop without a real isolation benefit. Mirrors `OpenFDAClient`'s
  shape.
- `PillScannerView` is built on VisionKit's `DataScannerViewController`
  (not raw AVCaptureSession). That mirrors `MedicationLabelScannerView`'s
  pattern and lets us reuse the same availability/permission contract.
  Symbology import requires `import Vision` alongside `import VisionKit`.
- `PillScannerView` is a leaf view (no NavigationStack) so the coordinator
  owns the title + Cancel/Use toolbar. The `detectedPayload` is bound
  upward instead of returned via callback — simplifies the "Use" gate.

## UPC → NDC normalization

US drug UPC-A codes are 12 digits and a leading `3` is the FDA's "drug
products" UCC prefix. The middle 10 digits encode the NDC10, ambiguously
split as 4-4-2, 5-3-2, or 5-4-1. openFDA's `product_ndc` field uses the
5-4 or 4-4 split. We try each format and return the first match. Candidates
ranked:

1. `XXXXX-XXXX` (5-4 split, drop leading `3` and trailing check digit)
2. `XXXX-XXXX` (4-4 split, drop leading `3`, last two, and trailing check)
3. `XXXXX-XXX` (5-3 split)

If the payload is already an NDC-format string (contains `-`), pass through
unchanged.

## Interaction heuristic

Case-insensitive overlap on `fdaIngredients` between the scanned result and
each `Medication` in the Circle's `medications` where `status == .active`.
For each overlap, emit one row: "Shares <ingredient> with <medication
name>." We do NOT order or rank — the user gets one row per overlap pair, in
the order ingredients appear in the scanned result.

Limitations called out in the result view:

> "Ingredient overlap is a starting point — it does not replace a
> pharmacist's interaction check."

## Triggers / state machine

`PillIdentifierView` state:

- `.scanning` — camera live, scanner running
- `.looking_up(payload: String)` — UPC captured, OpenFDA lookup in flight
- `.found(PillIdentificationResult, [InteractionRow])` — show result + apply CTA
- `.unknown(payload: String)` — UPC captured but no openFDA match; offer
  "Search by name" deep-link to AddMedicationView
- `.error(String)` — transient failure (transport, permission denied)

Camera permission flow: on first present, request authorization. Denied →
show explainer with "Open Settings" button.

## DOD checklist

- [x] Toolbar button added to MedicationListView, opens sheet
- [x] Camera permission requested + handled gracefully (via
      `DataScannerViewController.isAvailable` + `.isSupported`)
- [x] EAN-13 / UPC-A / Code-128 detection in scanner (plus EAN-8, UPC-E,
      Code-39 — matches what US pharmacies print)
- [x] Three NDC format candidates tried per scan (5-4, 4-4, 5-3 splits)
- [x] OpenFDA `/drug/ndc.json` lookup returns `OpenFDANDCResult`
- [x] Interaction overlap rows shown when ingredients match active circle meds
- [x] "Not medical advice" footer present on result view
- [x] "Add to medications" CTA pre-fills `MedicationDraft`
- [x] xcodebuild clean (BUILD SUCCEEDED, no warnings)
- [x] swiftformat + swiftlint clean (0 violations across the 12 touched files)
- [ ] Manual simulator pass — deferred to device QA (simulator can't drive
      the VisionKit barcode pipeline; the permission-denied and the
      "Add by name" fallback branches render on simulator)

## Commit message

`feat(ios): pill identifier — NDC barcode scan + ingredient overlap (Phase 32)`
