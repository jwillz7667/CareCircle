# Phase 11 — Care minutes log + PDF export

## End state
Paid family caregivers can log time spent on care tasks, tagged with HCBS
service codes, then export a weekly PDF formatted as a ready-to-edit
fiscal-intermediary timesheet. Manual entry is the v1 path; geofence
auto-detect is documented as a future TODO. A footer disclaimer is on
both the in-app log and the PDF: "Not a direct submission to any fiscal
intermediary — verify against your FI's requirements before submitting."

## Out-of-scope for this phase
- **Geofence auto-detect.** Needs `CLCircularRegion` monitoring + always-on
  location authorization. The privacy + battery cost is non-trivial and
  deserves a dedicated spike. Leave hooks but not the implementation.
- **Direct FI submission / EVV transmission.** Each state's
  Electronic Visit Verification spec is different — out of scope until
  we have a paying FI partner.
- **Mileage tracking automation.** Manual `milesDriven` field only.

## Build sequence

1. **`HCBSServiceCode.swift`** — small enum with the most common
   codes (T1019 Personal Care, S5125 Companion, S5170 Meal Prep,
   T2003 Non-emergency Transport, etc.) + display name + category.
   Codes sourced from CMS HCBS Taxonomy v3.2 and the PPL service
   catalog (most common state-Medicaid overlap).
2. **`CareMinuteEntry.swift`** — `@Model`: id, circle inverse,
   caregiverAppleUserID, caregiverDisplayName, serviceCode (raw
   string for forward-compat), serviceDescription, startedAt, endedAt,
   durationMinutes computed, notes, milesDriven, fiscalIntermediary
   (free text "PPL" / "Acumen" / etc.), exportedAt, createdAt,
   updatedAt. Add `[CareMinuteEntry]` inverse to `Circle`.
3. **`CareMinuteService.swift`** — pure helpers: weekRange(for:),
   totalMinutes(in:), groupedByDay(_:), groupedByServiceCode(_:).
4. **`CareMinuteListView.swift`** — calendar-week-pivoted list with a
   summary header (total hours this week, by service code), date
   navigation (prev / this week / next week), and per-entry rows.
   Empty state when nothing this week.
5. **`AddCareMinuteEntryView.swift`** — form: caregiver (auto-set to
   current user), service code picker, started/ended date pickers,
   notes, miles driven (optional), fiscal intermediary. Validation:
   end > start, both in the past.
6. **`CareMinuteEntryDetailView.swift`** — read + edit (own entries
   only) + delete (own entries only). Owner of circle can read all
   but not edit others' entries.
7. **`CareMinutePDFRenderer.swift`** — wraps `UIGraphicsPDFRenderer`
   to draw a Letter-sized timesheet: header (circle name, week range,
   caregiver, FI), table of entries (date / start / end / hours /
   service code / notes), totals row, signature line, disclaimer
   footer. Returns `Data` for ShareLink.
8. **`CareMinuteExportView.swift`** — week picker, "Generate PDF"
   button, preview the PDF in a `PDFView` (reused from Documents),
   ShareLink to export. On successful share, marks all entries in
   the week as `exportedAt = .now`.
9. **`MoreView` update** — add `Care minutes` NavLink under "Your Circle"
   between Documents and Emergency contacts.
10. **`CareCircleApp` schema update** — register `CareMinuteEntry.self`.
11. swiftformat + swiftlint clean.
12. xcodebuild green.
13. Commit + push.

## Risks / things to watch
- PDF rendering uses UIKit `UIGraphicsPDFRenderer` — already imported
  elsewhere, but the actual draw closure is non-main-actor in older
  iOS SDKs. iOS 26 default-MainActor isolation requires explicit
  `nonisolated` on the draw helpers or wrapping with
  `MainActor.assumeIsolated`.
- `Letter` paper size: use 612 × 792 points (8.5" × 11").
- HCBS codes are state- and FI-specific; v1 ships a 10-code starter
  list. Adding new codes is a one-line enum case addition — leave a
  TODO with the CMS taxonomy URL.

## Safety rules (carry-forward)
- No marketing language about being a payroll or billing system.
- Disclaimer must appear on the in-app summary AND the rendered PDF.
- Care Recipient data (name + DOB) appears on the PDF header for
  identification only; redact in any future shareable web export.

## Future TODOs left as comments in code
- `CareMinuteService`: geofence auto-detect when arriving at the
  recipient's address — needs always-on location + a stored geo
  anchor on `CareRecipient`.
- `CareMinutePDFRenderer`: per-FI template overrides (PPL vs Acumen
  vs Easterseals); currently a single generic layout.
- `CareMinuteExportView`: email-to-FI direct-send via `MFMailComposeViewController`.
