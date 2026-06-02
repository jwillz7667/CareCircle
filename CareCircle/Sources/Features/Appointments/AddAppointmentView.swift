import OSLog
import SwiftData
import SwiftUI

// MARK: - AddAppointmentView

/// Sheet for creating or editing an `Appointment` inside a Circle. Pass
/// `editing` to enter edit mode; pass `nil` to create.
struct AddAppointmentView: View {
    let circle: Circle
    let editing: Appointment?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(\.appointmentCalendarSync) private var calendarSync

    @State private var draft: AppointmentDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSeedMirrorState = false

    init(circle: Circle, editing: Appointment? = nil) {
        self.circle = circle
        self.editing = editing
        if let editing {
            // Calendar-mirror state is device-local; it's read from the
            // injected `calendarSync` in `.task` once the environment is
            // available, since `@Environment` can't be read in `init`.
            _draft = State(initialValue: AppointmentDraft(
                appointment: editing,
                mirrorToCalendar: false
            ))
        } else {
            _draft = State(initialValue: AppointmentDraft())
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
                scheduleSection
                AppointmentTransportPicker(
                    members: activeMembers,
                    selectedAppleUserID: $draft.transportResponsibleAppleUserID,
                    selectedDisplayName: $draft.transportResponsibleDisplayName
                )
                AppointmentReminderPicker(selectedOffsets: $draft.reminderOffsetsMinutes)
                calendarSection
                notesSection
                if isEditing { completionSection }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Color.ccDanger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
            .navigationTitle(isEditing ? "Edit appointment" : "Add appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
            .interactiveDismissDisabled(isSaving)
            .task {
                guard !didSeedMirrorState, let editing else { return }
                didSeedMirrorState = true
                draft.mirrorToCalendar = calendarSync.isMirroring(editing.id)
            }
        }
    }

    private var activeMembers: [Member] {
        circle.members
            .filter { $0.status == .active }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
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
    }

    private var identitySection: some View {
        Section {
            LabeledContent("Title") {
                TextField("e.g., Cardiology follow-up", text: $draft.title)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Appointment title")
            }
            LabeledContent("Provider") {
                TextField("Dr. Patel", text: $draft.provider)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Provider name")
            }
            LabeledContent("Location") {
                TextField("Address or video link", text: $draft.location)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Appointment location")
            }
        } header: {
            Text("Appointment")
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Starts", selection: $draft.startsAt, displayedComponents: [.date, .hourAndMinute])
            Picker("Duration", selection: $draft.durationMinutes) {
                ForEach(durationOptions, id: \.self) { minutes in
                    Text(durationLabel(forMinutes: minutes)).tag(minutes)
                }
            }
        }
    }

    private var calendarSection: some View {
        Section {
            Toggle("Sync to system Calendar", isOn: $draft.mirrorToCalendar)
                .accessibilityHint("Adds this appointment to your iPhone Calendar app.")
        } footer: {
            Text("Each device that opts in keeps its own Calendar entry. " +
                "Granting access prompts the first time.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                "Questions to ask, paperwork to bring, etc.",
                text: $draft.prepNotes,
                axis: .vertical
            )
            .lineLimit(2 ... 5)
        } header: {
            Text("Prep notes (optional)")
        }
    }

    private var completionSection: some View {
        Section("Visit summary") {
            Toggle("Mark as completed", isOn: $draft.markCompleted)
            if draft.markCompleted {
                TextField(
                    "How did it go? Decisions, follow-ups, results…",
                    text: $draft.visitSummary,
                    axis: .vertical
                )
                .lineLimit(3 ... 6)
            }
        }
    }

    private var durationOptions: [Int] {
        [15, 30, 45, 60, 90, 120, 180, 240]
    }

    private func durationLabel(forMinutes minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(remainder)m"
    }

    // MARK: - Actions

    private func save() {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let reminderScheduler = AppointmentReminderScheduler()
        let sync = calendarSync
        guard let target = isEditing ? applyEdit() : insertNew() else { return }
        let mirrorEnabled = draft.mirrorToCalendar
        Task {
            await rescheduleNotifications(for: target, scheduler: reminderScheduler)
            await syncCalendarMirror(for: target, enabled: mirrorEnabled, sync: sync)
        }
        dismiss()
    }

    private func applyEdit() -> Appointment? {
        guard let editing else { return nil }
        draft.apply(to: editing)
        do {
            try modelContext.save()
            return editing
        } catch {
            errorMessage = "Couldn't update the appointment. Please try again."
            AppLogger.persistence.error(
                "Appointment update failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func insertNew() -> Appointment? {
        let appointment = Appointment(
            title: draft.trimmedTitle,
            provider: draft.trimmedProvider.isEmpty ? nil : draft.trimmedProvider,
            location: draft.trimmedLocation.isEmpty ? nil : draft.trimmedLocation,
            startsAt: draft.startsAt,
            durationMinutes: draft.durationMinutes,
            prepNotes: draft.trimmedPrepNotes.isEmpty ? nil : draft.trimmedPrepNotes,
            visitSummary: draft.trimmedVisitSummary.isEmpty ? nil : draft.trimmedVisitSummary,
            transportResponsibleAppleUserID: draft.transportResponsibleAppleUserID,
            transportResponsibleDisplayName: draft.transportResponsibleDisplayName,
            reminderOffsetsMinutes: draft.reminderOffsetsMinutes,
            completedAt: draft.markCompleted ? (draft.completedAt ?? .now) : nil,
            createdByAppleUserID: circle.ownerAppleUserID,
            createdByDisplayName: circle.members.first(where: { $0.appleUserID == circle.ownerAppleUserID })?
                .displayName ?? ""
        )
        appointment.circle = circle
        modelContext.insert(appointment)
        do {
            try modelContext.save()
            syncEngine.enqueueAppointmentCreate(appointment)
            return appointment
        } catch {
            modelContext.delete(appointment)
            errorMessage = "Couldn't save the appointment. Please try again."
            AppLogger.persistence.error(
                "Appointment save failed: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
    }

    private func rescheduleNotifications(
        for appointment: Appointment,
        scheduler: AppointmentReminderScheduler
    ) async {
        await scheduler.registerCategoriesIfNeeded()
        guard appointment.completedAt == nil,
              !appointment.reminderOffsetsMinutes.isEmpty else
        {
            await scheduler.cancel(appointmentID: appointment.id)
            return
        }
        let granted = await scheduler.requestAuthorizationIfNeeded()
        guard granted else {
            AppLogger.app.notice("Notification permission denied; skipping appointment reminders.")
            return
        }
        await scheduler.reschedule(appointment: appointment)
    }

    private func syncCalendarMirror(
        for appointment: Appointment,
        enabled: Bool,
        sync: AppointmentCalendarSync
    ) async {
        if enabled {
            do {
                try await sync.upsert(for: appointment)
            } catch {
                AppLogger.app.error(
                    "Calendar mirror failed: \(String(describing: error), privacy: .public)"
                )
            }
        } else if sync.isMirroring(appointment.id) {
            await sync.remove(for: appointment.id)
        }
    }
}
