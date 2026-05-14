import OSLog
import SwiftData
import SwiftUI

// MARK: - AddCareMinuteEntryView

/// Sheet for creating or editing a single block of paid care time.
/// Validates that end > start and that the entry doesn't extend into
/// the future. Caregiver identity is stamped from the signed-in user;
/// non-owner members cannot author entries on behalf of someone else.
struct AddCareMinuteEntryView: View {
    let circle: Circle
    let viewerAppleUserID: String
    let viewerDisplayName: String
    let editing: CareMinuteEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var syncEngine

    @State private var serviceCode: HCBSServiceCode
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var notes: String
    @State private var milesText: String
    @State private var fiscalIntermediary: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        circle: Circle,
        viewerAppleUserID: String,
        viewerDisplayName: String,
        editing: CareMinuteEntry? = nil,
        anchorDate: Date = .now
    ) {
        self.circle = circle
        self.viewerAppleUserID = viewerAppleUserID
        self.viewerDisplayName = viewerDisplayName
        self.editing = editing

        if let editing {
            _serviceCode = State(initialValue: editing.serviceCode)
            _startedAt = State(initialValue: editing.startedAt)
            _endedAt = State(initialValue: editing.endedAt)
            _notes = State(initialValue: editing.notes ?? "")
            _milesText = State(initialValue: editing.milesDriven.map { String(format: "%.1f", $0) } ?? "")
            _fiscalIntermediary = State(initialValue: editing.fiscalIntermediary ?? "")
        } else {
            let calendar = Calendar.current
            let baseStart = calendar.dateInterval(of: .hour, for: anchorDate)?.start ?? anchorDate
            let baseEnd = calendar.date(byAdding: .hour, value: 1, to: baseStart) ?? baseStart
            _serviceCode = State(initialValue: .personalCare)
            _startedAt = State(initialValue: baseStart)
            _endedAt = State(initialValue: baseEnd)
            _notes = State(initialValue: "")
            _milesText = State(initialValue: "")
            _fiscalIntermediary = State(initialValue: "")
        }
    }

    private var isEditing: Bool {
        editing != nil
    }

    private var durationMinutes: Int {
        let seconds = endedAt.timeIntervalSince(startedAt)
        return max(0, Int(seconds / 60))
    }

    private var durationLabel: String {
        let minutes = durationMinutes
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(remainder)m"
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFI: String {
        fiscalIntermediary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedMiles: Double? {
        let trimmed = milesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        guard endedAt > startedAt else { return false }
        guard endedAt <= Date.now.addingTimeInterval(60) else { return false }
        if !milesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, parsedMiles == nil {
            return false
        }
        return durationMinutes > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                serviceSection
                scheduleSection
                detailsSection

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Color.ccDanger)
                    }
                }

                Section {
                    Text(disclaimer)
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle(isEditing ? "Edit entry" : "Log time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSaving)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }.disabled(!canSave)
        }
    }

    private var serviceSection: some View {
        Section("Service") {
            Picker("Service code", selection: $serviceCode) {
                ForEach(HCBSServiceCode.allCases) { code in
                    Label(code.displayName, systemImage: code.symbol).tag(code)
                }
            }
            LabeledContent("Code", value: serviceCode.rawValue)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    private var scheduleSection: some View {
        Section {
            DatePicker(
                "Start",
                selection: $startedAt,
                in: ...Date.now.addingTimeInterval(60),
                displayedComponents: [.date, .hourAndMinute]
            )
            DatePicker(
                "End",
                selection: $endedAt,
                in: startedAt ... Date.now.addingTimeInterval(60),
                displayedComponents: [.date, .hourAndMinute]
            )
            LabeledContent("Duration", value: durationLabel)
                .foregroundStyle(Color.ccText)
        } header: {
            Text("When")
        } footer: {
            if endedAt <= startedAt {
                Text("End time must be after start time.")
                    .foregroundStyle(Color.ccDanger)
            } else if endedAt > Date.now.addingTimeInterval(60) {
                Text("Entries can't extend into the future.")
                    .foregroundStyle(Color.ccDanger)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            LabeledContent("Miles driven") {
                TextField("Optional", text: $milesText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Miles driven, optional")
            }
            LabeledContent("Fiscal intermediary") {
                TextField("PPL, Acumen, Easterseals…", text: $fiscalIntermediary)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Fiscal intermediary")
            }
            TextField(
                "Notes (tasks completed, anything to flag)",
                text: $notes,
                axis: .vertical
            )
            .lineLimit(2 ... 5)
            .accessibilityLabel("Notes")
        }
    }

    private var disclaimer: String {
        "This log is for your records and any timesheet you submit to a " +
            "fiscal intermediary. CareCircle does not submit hours to any " +
            "payer on your behalf."
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let inserted: CareMinuteEntry?
        if let editing {
            applyEdit(to: editing)
            inserted = nil
        } else {
            inserted = insertNew()
        }

        do {
            try modelContext.save()
            if let inserted {
                syncEngine.enqueueCareMinuteCreate(inserted)
            }
            dismiss()
        } catch {
            errorMessage = "Couldn't save the entry. Please try again."
            AppLogger.persistence.error(
                "CareMinuteEntry save failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func applyEdit(to entry: CareMinuteEntry) {
        entry.serviceCode = serviceCode
        entry.serviceDescription = serviceCode.displayName
        entry.startedAt = startedAt
        entry.endedAt = endedAt
        entry.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        entry.milesDriven = parsedMiles
        entry.fiscalIntermediary = trimmedFI.isEmpty ? nil : trimmedFI
        entry.updatedAt = .now
    }

    private func insertNew() -> CareMinuteEntry {
        let entry = CareMinuteEntry(
            caregiverAppleUserID: viewerAppleUserID,
            caregiverDisplayName: viewerDisplayName,
            serviceCode: serviceCode,
            serviceDescription: serviceCode.displayName,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            milesDriven: parsedMiles,
            fiscalIntermediary: trimmedFI.isEmpty ? nil : trimmedFI
        )
        entry.circle = circle
        modelContext.insert(entry)
        return entry
    }
}
