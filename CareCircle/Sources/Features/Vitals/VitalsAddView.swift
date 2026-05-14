import SwiftData
import SwiftUI

// MARK: - VitalsAddView

/// Sheet for caregiver-entered vital readings. Only the eight manual
/// kinds are listed in the kind picker — HealthKit-only kinds (falls,
/// walking steadiness, sleep, resting HR, step count) are imported
/// automatically to avoid double-counting.
///
/// The form gives one numeric field for the value, a unit display
/// derived from the kind (no unit picker in v1 — backend canonicalizes
/// per kind), an optional notes field, and a date/time picker that
/// defaults to "now." Saving inserts a `Vital` with `source = .manual`
/// and enqueues the sync operation; the caller's `circle.vitals` query
/// picks it up immediately.
struct VitalsAddView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var kind: VitalKind = .heartRate
    @State private var valueString = ""
    @State private var notes = ""
    @State private var recordedAt: Date = .now
    @State private var saveError: String?

    private var parsedValue: Double? {
        let trimmed = valueString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private var isOutOfSanityRange: Bool {
        guard let value = parsedValue else { return false }
        return !kind.sanityRange.contains(value)
    }

    private var canSave: Bool {
        parsedValue != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading") {
                    Picker("Kind", selection: $kind) {
                        ForEach(VitalKind.manualEntryKinds) { kind in
                            Label(kind.displayName, systemImage: kind.systemImageName)
                                .tag(kind)
                        }
                    }

                    HStack {
                        TextField("Value", text: $valueString)
                            .keyboardType(keyboardType(for: kind))
                            .accessibilityLabel("Vital value")
                        Text(kind.defaultUnit)
                            .foregroundStyle(Color.ccSecondary)
                            .accessibilityHidden(true)
                    }

                    if isOutOfSanityRange {
                        Label(
                            "Outside the expected range (\(formattedRange(kind.sanityRange)) \(kind.defaultUnit)). Double-check this reading.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(Color.ccDanger)
                    }

                    DatePicker(
                        "Recorded",
                        selection: $recordedAt,
                        in: ...Date.now
                    )
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(Color.ccDanger)
                    }
                }

                Section {
                    DisclaimerFooter()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle("Add reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let value = parsedValue else { return }
        let vital = Vital(
            kind: kind,
            recordedAt: recordedAt,
            valueNumeric: value,
            unit: kind.defaultUnit,
            source: .manual,
            notes: notes.isEmpty ? nil : notes,
            recordedByAppleUserID: author.appleUserID,
            recordedByDisplayName: author.displayName
        )
        vital.circle = circle
        modelContext.insert(vital)
        do {
            try modelContext.save()
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            return
        }
        syncEngine.enqueueVitalCreate(vital)
        dismiss()
    }

    private func keyboardType(for kind: VitalKind) -> UIKeyboardType {
        switch kind {
        case .bodyWeight, .bodyTemperature: .decimalPad
        default: .numbersAndPunctuation
        }
    }

    private func formattedRange(_ range: ClosedRange<Double>) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0
        let lower = formatter.string(from: NSNumber(value: range.lowerBound)) ?? "\(range.lowerBound)"
        let upper = formatter.string(from: NSNumber(value: range.upperBound)) ?? "\(range.upperBound)"
        return "\(lower)–\(upper)"
    }
}
