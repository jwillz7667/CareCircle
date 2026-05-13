import OSLog
import SwiftData
import SwiftUI

// MARK: - CareMinuteEntryDetailView

/// Read-only by default; the caregiver who logged the entry can edit or
/// delete via the toolbar. Circle owner can read all entries but not
/// edit anyone else's — billing records are not theirs to rewrite.
struct CareMinuteEntryDetailView: View {
    let entry: CareMinuteEntry
    let viewerAppleUserID: String
    let canManage: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var viewerDisplayName: String {
        entry.circle?.members.first(where: { $0.appleUserID == viewerAppleUserID })?.displayName ?? ""
    }

    var body: some View {
        List {
            heroSection
            scheduleSection
            detailsSection
            metadataSection

            if let deleteError {
                Section {
                    Label(deleteError, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(Color.ccDanger)
                }
            }

            if canManage {
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ccBackground)
        .navigationTitle(entry.serviceCode.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .toolbar {
            if canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let circle = entry.circle {
                AddCareMinuteEntryView(
                    circle: circle,
                    viewerAppleUserID: viewerAppleUserID,
                    viewerDisplayName: viewerDisplayName,
                    editing: entry
                )
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(durationLabel) of logged time. It can't be undone.")
        }
    }

    private var heroSection: some View {
        Section {
            HStack(spacing: Theme.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.ccSurface)
                        .frame(width: 60, height: 60)
                    Image(systemName: entry.serviceCode.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.ccPrimary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.serviceCode.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Text("HCBS code \(entry.serviceCode.rawValue)")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                    if entry.exportedAt != nil {
                        Label("Exported", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.ccPrimary)
                    }
                }
                Spacer()
                Text(String(format: "%.2fh", entry.durationHours))
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.ccText)
            }
            .padding(.vertical, Theme.tightSpacing / 2)
        }
    }

    private var scheduleSection: some View {
        Section("When") {
            LabeledContent("Date", value: entry.startedAt.formatted(date: .complete, time: .omitted))
                .foregroundStyle(Color.ccText)
            LabeledContent("Start", value: entry.startedAt.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(Color.ccText)
            LabeledContent("End", value: entry.endedAt.formatted(date: .omitted, time: .shortened))
                .foregroundStyle(Color.ccText)
            LabeledContent("Duration", value: durationLabel)
                .foregroundStyle(Color.ccText)
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        let trimmedNotes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedFI = entry.fiscalIntermediary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedNotes.isEmpty || entry.milesDriven != nil || !trimmedFI.isEmpty {
            Section("Details") {
                if let miles = entry.milesDriven {
                    LabeledContent("Miles driven", value: String(format: "%.1f", miles))
                        .foregroundStyle(Color.ccText)
                }
                if !trimmedFI.isEmpty {
                    LabeledContent("Fiscal intermediary", value: trimmedFI)
                        .foregroundStyle(Color.ccText)
                }
                if !trimmedNotes.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                        Text("Notes")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.ccSecondary)
                        Text(trimmedNotes)
                            .font(.body)
                            .foregroundStyle(Color.ccText)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var metadataSection: some View {
        Section("Logged by") {
            LabeledContent(
                "Caregiver",
                value: entry.caregiverDisplayName.isEmpty ? "Unknown" : entry.caregiverDisplayName
            )
            .foregroundStyle(Color.ccText)
            LabeledContent("Logged", value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(Color.ccSecondary)
            if entry.updatedAt > entry.createdAt {
                LabeledContent("Updated", value: entry.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(Color.ccSecondary)
            }
            if let exportedAt = entry.exportedAt {
                LabeledContent("Exported", value: exportedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete entry", systemImage: "trash")
            }
        }
    }

    private var durationLabel: String {
        let minutes = entry.durationMinutes
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(remainder)m"
    }

    private func delete() {
        do {
            modelContext.delete(entry)
            try modelContext.save()
            dismiss()
        } catch {
            deleteError = "Couldn't delete the entry. Please try again."
            AppLogger.persistence.error(
                "CareMinuteEntry delete failed: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
