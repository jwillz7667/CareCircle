import OSLog
import SwiftData
import SwiftUI

// MARK: - MedicationDetailView

/// Detail screen for a single medication. Shows identity + schedule summary,
/// dose history for the recent ±7-day window, and edit/delete actions.
struct MedicationDetailView: View {
    let medication: Medication
    let author: ActivityAuthorContext

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var doseRows: [MedicationDoseRow.Occurrence] {
        let now = Date()
        let calendar = Calendar.current
        let lookbackStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let lookaheadEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? now

        let recorded = medication.doseEvents
            .filter { $0.scheduledAt >= lookbackStart && $0.scheduledAt <= lookaheadEnd }
        let recordedSet = Set(recorded.map(\.scheduledAt))

        let upcoming = medication.schedule
            .upcomingOccurrences(after: now, limit: 8)
            .filter { !recordedSet.contains($0) }

        var entries: [MedicationDoseRow.Occurrence] = recorded.map { .recorded($0) }
        entries.append(contentsOf: upcoming.map { .scheduled($0) })
        entries.sort { $0.date > $1.date }
        return entries
    }

    var body: some View {
        List {
            heroSection
            scheduleSection
            historySection
            ingredientsSection
            disclaimerSection

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
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let circle = medication.circle {
                AddMedicationView(circle: circle, editing: medication)
            }
        }
        .confirmationDialog(
            "Delete this medication?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the medication and its dose history. Past activity-feed posts stay.")
        }
    }

    private var heroSection: some View {
        Section {
            HStack(alignment: .center, spacing: Theme.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.ccSurface)
                        .frame(width: 60, height: 60)
                    Image(systemName: medication.form.systemImageName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.ccPrimary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.dosage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Text(medication.form.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                    Text(medication.status.displayName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(statusColor)
                }
                Spacer()
            }
            .padding(.vertical, Theme.tightSpacing / 2)
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            Text(medication.schedule.summary())
                .foregroundStyle(Color.ccText)

            if let instructions = medication.instructions, !instructions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instructions")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.ccSecondary)
                    Text(instructions)
                        .foregroundStyle(Color.ccText)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !doseRows.isEmpty {
            Section("Doses") {
                ForEach(Array(doseRows.enumerated()), id: \.offset) { _, row in
                    MedicationDoseRow(
                        medication: medication,
                        occurrence: row,
                        author: author,
                        onMarked: { _ in }
                    )
                }
            }
        } else if medication.status == .active,
                  medication.schedule.frequency != .asNeeded
        {
            Section("Doses") {
                Text("No doses recorded in the past week.")
                    .font(.subheadline)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        if !medication.fdaIngredients.isEmpty {
            Section("Active ingredients") {
                Text(medication.fdaIngredients.joined(separator: ", "))
                    .foregroundStyle(Color.ccText)
            }
        }
    }

    private var disclaimerSection: some View {
        Section {
            MedicationDisclaimerFooter()
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete medication", systemImage: "trash")
            }
        }
    }

    private var statusColor: Color {
        switch medication.status {
        case .active: Color.ccPrimary
        case .asNeeded: Color.ccSecondary
        case .discontinued: Color.ccDanger
        }
    }

    private func delete() {
        let medicationID = medication.id
        let scheduler = MedicationReminderScheduler()
        Task { await scheduler.cancel(medicationID: medicationID) }

        modelContext.delete(medication)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            deleteError = "Couldn't delete the medication."
            AppLogger.persistence.error(
                "Medication delete failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
