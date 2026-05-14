import OSLog
import SwiftData
import SwiftUI

// MARK: - PillIdentifierView

/// Sheet-level coordinator for the pill-identification flow. Owns a
/// finite state machine: `.scanning` → `.lookingUp` → `.found` /
/// `.unknown` / `.error`. Each phase renders inline inside a single
/// NavigationStack so the user only ever sees one sheet — when they
/// accept a result, a child `AddMedicationView` sheet stacks on top.
///
/// Designed to be presented from `MedicationListView`'s toolbar via
/// `.sheet(isPresented:)`. The Circle is read from the parent because
/// every Medication in the app is Circle-scoped and the interaction
/// overlap check needs the active-medication set for that Circle.
struct PillIdentifierView: View {
    let circle: Circle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .scanning
    @State private var scannerPayload: String?
    @State private var pendingAdd: PendingAddSheet?

    private let identifier = PillIdentifier()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Identify pill")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(navigationBackground, for: .navigationBar)
                .toolbarColorScheme(isScanning ? .dark : nil, for: .navigationBar)
                .toolbar { toolbar }
                .background(contentBackground)
        }
        .sheet(
            item: $pendingAdd,
            onDismiss: { dismiss() },
            content: { pending in
                AddMedicationView(
                    circle: circle,
                    initialDraft: MedicationDraft(identification: pending.result)
                )
            }
        )
    }

    private var navigationBackground: Color {
        isScanning ? Color.black : Color.ccBackground
    }

    private var contentBackground: Color {
        isScanning ? Color.black : Color.ccBackground
    }

    private var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(isScanning ? "Cancel" : "Done") {
                dismiss()
            }
            .tint(isScanning ? Color.white : nil)
        }
        if isScanning {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use") {
                    if let payload = scannerPayload {
                        handleScan(payload: payload)
                    }
                }
                .tint(Color.white)
                .disabled(scannerPayload == nil)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            PillScannerView(detectedPayload: $scannerPayload)
        case let .lookingUp(payload):
            lookupView(payload: payload)
        case let .found(result, matches):
            PillIdentifierResultView(
                result: result,
                interactions: matches,
                onAdd: { pendingAdd = PendingAddSheet(result) }
            )
        case let .unknown(payload):
            unknownView(payload: payload)
        case let .error(message, payload):
            errorView(message: message, payload: payload)
        }
    }

    private func lookupView(payload: String) -> some View {
        VStack(spacing: Theme.spacing) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.ccPrimary)
            VStack(spacing: 4) {
                Text("Looking up barcode…")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(payload)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color.ccSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.spacing)
    }

    private func unknownView(payload: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Label("No openFDA match", systemImage: "questionmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccText)

                scannedBarcodeCard(payload: payload)

                Text(
                    "We couldn't match this barcode against openFDA's NDC directory. That's common for OTC and international products. You can still add the medication manually."
                )
                .font(.body)
                .foregroundStyle(Color.ccText)

                unknownActions(payload: payload)

                Text("Not medical advice — consult your healthcare provider.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.spacing)
        }
    }

    private func errorView(message: String, payload: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Label("Lookup failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccDanger)

                Text(message)
                    .font(.body)
                    .foregroundStyle(Color.ccText)

                scannedBarcodeCard(payload: payload)

                errorActions(payload: payload)
            }
            .padding(Theme.spacing)
        }
    }

    private func scannedBarcodeCard(payload: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text("Scanned barcode")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ccSecondary)
            Text(payload)
                .font(.body.monospaced())
                .foregroundStyle(Color.ccText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }

    private func unknownActions(payload: String) -> some View {
        VStack(spacing: Theme.tightSpacing) {
            Button {
                pendingAdd = PendingAddSheet(emptyDraftFromPayload: payload)
            } label: {
                Label("Add by name", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ccPrimary)

            Button {
                resetForRescan()
            } label: {
                Label("Scan again", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(Color.ccPrimary)
        }
    }

    private func errorActions(payload: String) -> some View {
        VStack(spacing: Theme.tightSpacing) {
            Button {
                handleScan(payload: payload)
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ccPrimary)

            Button {
                resetForRescan()
            } label: {
                Label("Scan a different barcode", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(Color.ccPrimary)
        }
    }

    // MARK: - Actions

    private func handleScan(payload: String) {
        phase = .lookingUp(payload: payload)
        Task {
            do {
                let lookup = try await identifier.identify(payload: payload)
                if let lookup {
                    let medications = fetchCircleMedications()
                    let matches = InteractionChecker.matches(for: lookup, against: medications)
                    phase = .found(lookup, matches)
                    AppLogger.app.info(
                        "Pill identifier surfaced result for NDC \(lookup.matchedNDC, privacy: .public) (overlaps=\(matches.count))."
                    )
                } else {
                    phase = .unknown(payload: payload)
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "Something went wrong reaching openFDA. Try again in a moment."
                phase = .error(message: message, payload: payload)
                AppLogger.app.error(
                    "Pill identifier lookup failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func resetForRescan() {
        scannerPayload = nil
        phase = .scanning
    }

    private func fetchCircleMedications() -> [Medication] {
        let circleID = circle.id
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate<Medication> { medication in
                medication.circle?.id == circleID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

// MARK: - Phase

private extension PillIdentifierView {
    enum Phase: Equatable {
        case scanning
        case lookingUp(payload: String)
        case found(PillIdentificationResult, [InteractionChecker.Match])
        case unknown(payload: String)
        case error(message: String, payload: String)
    }
}

// MARK: - PendingAddSheet

/// Wrapper to satisfy `.sheet(item:)`'s Identifiable requirement without
/// adding `Identifiable` to `PillIdentificationResult` itself. Stores
/// either a scanned result (pre-filled draft) or nil (for the "Add by
/// name" path on unknown barcodes, which presents an empty draft).
private struct PendingAddSheet: Identifiable {
    let id: String
    let result: PillIdentificationResult

    init(_ result: PillIdentificationResult) {
        id = result.matchedNDC
        self.result = result
    }

    init(emptyDraftFromPayload payload: String) {
        id = "manual-\(payload)"
        result = PillIdentificationResult(
            scannedPayload: payload,
            matchedNDC: "",
            brandNames: [],
            genericNames: [],
            activeIngredients: [],
            routes: [],
            dosageForms: []
        )
    }
}
