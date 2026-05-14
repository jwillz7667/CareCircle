import SwiftData
import SwiftUI

// MARK: - MedicationDoseRow

/// Row used inside `MedicationDetailView`'s dose-history list. Lets the user
/// mark an upcoming dose as taken or skipped, and shows the recorded status
/// (with marker) for past doses.
struct MedicationDoseRow: View {
    let medication: Medication
    let occurrence: Occurrence
    let author: ActivityAuthorContext
    let onMarked: (DoseStatus) -> Void

    enum Occurrence: Equatable {
        case scheduled(Date)
        case recorded(DoseEvent)

        var date: Date {
            switch self {
            case let .scheduled(date): date
            case let .recorded(event): event.scheduledAt
            }
        }

        var event: DoseEvent? {
            if case let .recorded(event) = self { return event }
            return nil
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(SyncEngine.self) private var syncEngine
    @Environment(InsightsEngine.self) private var insightsEngine

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(occurrence.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                statusLine
                if let markerLine {
                    Text(markerLine)
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
            }

            Spacer()

            actionButtons
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch occurrence {
        case .scheduled:
            if occurrence.date < Date() {
                Text("Missed")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.ccDanger)
            } else {
                Text("Scheduled")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
        case let .recorded(event):
            Text(event.status.displayName)
                .font(.footnote.weight(.medium))
                .foregroundStyle(color(for: event.status))
            if let takenAt = event.takenAt, event.status == .taken || event.status == .late {
                Text("Taken \(takenAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private var markerLine: String? {
        if case let .recorded(event) = occurrence,
           let name = event.markedByDisplayName, !name.isEmpty
        {
            return "Logged by \(name)"
        }
        return nil
    }

    @ViewBuilder
    private var actionButtons: some View {
        if shouldShowActions {
            HStack(spacing: Theme.tightSpacing) {
                Button {
                    mark(as: .taken)
                } label: {
                    Label("Taken", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(Color.ccPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark dose taken")

                Button {
                    mark(as: .skipped)
                } label: {
                    Label("Skip", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .foregroundStyle(Color.ccDanger)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark dose skipped")
            }
        }
    }

    private var shouldShowActions: Bool {
        switch occurrence {
        case .scheduled:
            true
        case let .recorded(event):
            event.status == .scheduled || event.status == .missed
        }
    }

    private func mark(as status: DoseStatus) {
        let marker = author.hasIdentity
            ? DoseEventApplicator.Marker(
                appleUserID: author.appleUserID,
                displayName: author.displayName
            )
            : nil
        let dose = DoseEventApplicator.apply(
            status: status,
            scheduledAt: occurrence.date,
            medication: medication,
            in: modelContext,
            marker: marker
        )
        try? modelContext.save()
        switch status {
        case .taken, .late:
            syncEngine.enqueueDoseTaken(dose)
        case .skipped:
            syncEngine.enqueueDoseSkipped(dose)
        case .scheduled, .missed:
            break
        }
        if let circle = medication.circle {
            insightsEngine.recomputeDebounced(circle: circle, modelContext: modelContext)
        }
        onMarked(status)
    }

    private func color(for status: DoseStatus) -> Color {
        switch status {
        case .taken, .late: Color.ccPrimary
        case .skipped: Color.ccSecondary
        case .missed: Color.ccDanger
        case .scheduled: Color.ccSecondary
        }
    }
}
