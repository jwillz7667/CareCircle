import OSLog
import SwiftData
import SwiftUI

// MARK: - AddMedicationView

/// Sheet for creating or editing a `Medication` inside a Circle. Pass
/// `medication` to enter edit mode; pass `nil` to create.
struct AddMedicationView: View {
    let circle: Circle
    let editing: Medication?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var syncEngine

    @State private var draft: MedicationDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var hasStartDate: Bool
    @State private var hasEndDate: Bool
    @State private var isPresentingScanner = false

    init(circle: Circle, editing: Medication? = nil) {
        self.circle = circle
        self.editing = editing
        if let editing {
            _draft = State(initialValue: MedicationDraft(medication: editing))
            _hasStartDate = State(initialValue: editing.startDate != nil)
            _hasEndDate = State(initialValue: editing.endDate != nil)
        } else {
            _draft = State(initialValue: MedicationDraft())
            _hasStartDate = State(initialValue: false)
            _hasEndDate = State(initialValue: false)
        }
    }

    private var isEditing: Bool {
        editing != nil
    }

    private var canSave: Bool {
        !isSaving && draft.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                MedicationScheduleEditor(schedule: $draft.schedule)
                statusSection
                MedicationFDASection(
                    queryName: draft.trimmedName,
                    savedIngredients: $draft.fdaIngredients
                )
                datesSection
                instructionsSection

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Color.ccDanger)
                    }
                }

                Section {
                    MedicationDisclaimerFooter()
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle(isEditing ? "Edit medication" : "Add medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSaving)
            .sheet(isPresented: $isPresentingScanner) {
                MedicationLabelScannerView { suggestion in
                    applyScannerSuggestion(suggestion)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .disabled(!canSave)
        }
        if !isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingScanner = true
                } label: {
                    Label("Scan label", systemImage: "camera.viewfinder")
                }
                .disabled(isSaving)
                .accessibilityLabel("Scan medication label with camera")
            }
        }
    }

    private var identitySection: some View {
        Section {
            LabeledContent("Name") {
                TextField("e.g., Lisinopril", text: $draft.name)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Medication name")
            }

            LabeledContent("Dose") {
                TextField("e.g., 10 mg", text: $draft.dosage)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Dose amount")
            }

            Picker("Form", selection: $draft.form) {
                ForEach(MedicationForm.allCases, id: \.self) { form in
                    Label(form.displayName, systemImage: form.systemImageName).tag(form)
                }
            }
        } header: {
            Text("Medication")
        } footer: {
            Text("Use the exact wording from the prescription label.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            Picker("Status", selection: $draft.status) {
                ForEach(MedicationStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var datesSection: some View {
        Section("Dates") {
            Toggle("Start date", isOn: $hasStartDate)
                .onChange(of: hasStartDate) { _, newValue in
                    draft.startDate = newValue ? (draft.startDate ?? Date()) : nil
                }
            if hasStartDate {
                DatePicker(
                    "Started on",
                    selection: Binding(
                        get: { draft.startDate ?? Date() },
                        set: { draft.startDate = $0 }
                    ),
                    displayedComponents: .date
                )
            }

            Toggle("End date", isOn: $hasEndDate)
                .onChange(of: hasEndDate) { _, newValue in
                    draft.endDate = newValue ? (draft.endDate ?? Date()) : nil
                }
            if hasEndDate {
                DatePicker(
                    "Ends on",
                    selection: Binding(
                        get: { draft.endDate ?? Date() },
                        set: { draft.endDate = $0 }
                    ),
                    displayedComponents: .date
                )
            }
        }
    }

    private var instructionsSection: some View {
        Section {
            TextField(
                "Take with food, avoid grapefruit, etc.",
                text: $draft.instructions,
                axis: .vertical
            )
            .lineLimit(2 ... 5)
        } header: {
            Text("Instructions (optional)")
        }
    }

    // MARK: - Actions

    private func save() {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let scheduler = MedicationReminderScheduler()
        guard let target = isEditing ? applyEdit() : insertNew() else { return }
        Task { await rescheduleNotifications(for: target, scheduler: scheduler) }
        dismiss()
    }

    private func applyEdit() -> Medication? {
        guard let editing else { return nil }
        draft.apply(to: editing)
        do {
            try modelContext.save()
            return editing
        } catch {
            errorMessage = "Couldn't update the medication. Please try again."
            AppLogger.persistence.error(
                "Medication update failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func insertNew() -> Medication? {
        let medication = Medication(
            name: draft.trimmedName,
            dosage: draft.trimmedDosage,
            form: draft.form,
            status: draft.status,
            schedule: draft.schedule,
            instructions: draft.trimmedInstructions.isEmpty ? nil : draft.trimmedInstructions,
            colorHex: draft.colorHex,
            fdaIngredients: draft.fdaIngredients,
            startDate: draft.startDate,
            endDate: draft.endDate
        )
        medication.circle = circle
        modelContext.insert(medication)
        do {
            try modelContext.save()
            syncEngine.enqueueMedicationCreate(medication)
            return medication
        } catch {
            modelContext.delete(medication)
            errorMessage = "Couldn't save the medication. Please try again."
            AppLogger.persistence.error(
                "Medication save failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func rescheduleNotifications(
        for medication: Medication,
        scheduler: MedicationReminderScheduler
    ) async {
        await scheduler.registerCategoriesIfNeeded()
        guard medication.status == .active,
              medication.schedule.frequency != .asNeeded,
              !medication.schedule.timesOfDay.isEmpty else
        {
            await scheduler.cancel(medicationID: medication.id)
            return
        }
        let granted = await scheduler.requestAuthorizationIfNeeded()
        guard granted else {
            AppLogger.app.notice("Notification permission denied; skipping reminders.")
            return
        }
        await scheduler.reschedule(medication: medication)
    }

    private func applyScannerSuggestion(_ suggestion: MedicationLabelSuggestion) {
        if !suggestion.name.isEmpty {
            draft.name = suggestion.name
        }
        if let dosage = suggestion.dosage, !dosage.isEmpty {
            draft.dosage = dosage
        }
        if let form = suggestion.form {
            draft.form = form
        }
    }
}
