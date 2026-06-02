import OSLog
import SwiftData
import SwiftUI

// MARK: - AppointmentDetailView

/// Detail screen for a single appointment. Shows the schedule hero, prep
/// notes, visit summary (if completed), and edit/delete actions. Calendar
/// mirror state lives on this device only, so we surface it as a status row
/// here rather than syncing across members.
struct AppointmentDetailView: View {
    let appointment: Appointment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appointmentCalendarSync) private var calendarSync

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?
    @State private var isMirroring = false

    var body: some View {
        List {
            heroSection
            scheduleSection
            transportSection
            remindersSection
            calendarMirrorSection
            prepSection
            summarySection

            if let deleteError {
                Section {
                    Label(deleteError, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Color.ccDanger)
                }
            }

            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle(appointment.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let circle = appointment.circle {
                AddAppointmentView(circle: circle, editing: appointment)
            }
        }
        .task(id: appointment.id) {
            isMirroring = calendarSync.isMirroring(appointment.id)
        }
        .confirmationDialog(
            "Delete this appointment?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reminders and Calendar mirror are removed too.")
        }
    }

    private var heroSection: some View {
        Section {
            HStack(alignment: .center, spacing: Theme.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.ccSurface)
                        .frame(width: 60, height: 60)
                    Image(systemName: appointment.isCompleted ? "checkmark.circle.fill" : "calendar")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.ccPrimary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(appointment.startsAt.formatted(date: .complete, time: .shortened))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Text(durationDescription)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                    if appointment.isCompleted {
                        Text("Completed")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.ccPrimary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, Theme.tightSpacing / 2)
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            if let provider = appointment.provider?.trimmingCharacters(in: .whitespacesAndNewlines),
               !provider.isEmpty
            {
                LabeledContent("Provider", value: provider)
            }
            if let location = appointment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !location.isEmpty
            {
                LabeledContent("Location", value: location)
            }
            LabeledContent("Ends", value: appointment.endsAt.formatted(date: .omitted, time: .shortened))
        }
    }

    @ViewBuilder
    private var transportSection: some View {
        if let transport = appointment.transportResponsibleDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !transport.isEmpty
        {
            Section("Transportation") {
                Label("\(transport) driving", systemImage: "car.fill")
                    .foregroundStyle(Color.ccPrimary)
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        if !appointment.reminderOffsetsMinutes.isEmpty {
            Section("Reminders") {
                ForEach(appointment.reminderOffsetsMinutes.sorted(), id: \.self) { minutes in
                    Text(reminderLabel(forMinutes: minutes))
                        .foregroundStyle(Color.ccText)
                }
            }
        }
    }

    private var calendarMirrorSection: some View {
        Section("System Calendar") {
            if isMirroring {
                Label("Mirrored to your iPhone Calendar", systemImage: "calendar.badge.checkmark")
                    .foregroundStyle(Color.ccPrimary)
            } else {
                Label("Not synced to system Calendar", systemImage: "calendar")
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    @ViewBuilder
    private var prepSection: some View {
        if let prep = appointment.prepNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prep.isEmpty
        {
            Section("Prep notes") {
                Text(prep).foregroundStyle(Color.ccText)
            }
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        if let summary = appointment.visitSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty
        {
            Section("Visit summary") {
                Text(summary).foregroundStyle(Color.ccText)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete appointment", systemImage: "trash")
            }
        }
    }

    private var durationDescription: String {
        let minutes = appointment.durationMinutes
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(remainder)m"
    }

    private func reminderLabel(forMinutes minutes: Int) -> String {
        let interval = TimeInterval(minutes) * 60
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(formatter.localizedString(fromTimeInterval: interval)) before"
    }

    private func delete() {
        let appointmentID = appointment.id
        let scheduler = AppointmentReminderScheduler()
        let sync = calendarSync
        Task {
            await scheduler.cancel(appointmentID: appointmentID)
            await sync.remove(for: appointmentID)
        }

        modelContext.delete(appointment)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            deleteError = "Couldn't delete the appointment."
            AppLogger.persistence.error(
                "Appointment delete failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
