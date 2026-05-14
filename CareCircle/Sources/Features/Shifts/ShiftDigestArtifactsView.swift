import SwiftUI

// MARK: - ShiftDigestArtifactsView

/// Renders the structured-event snapshot attached to a shift digest.
/// Shared between the composer (live preview while picking a window)
/// and the detail view (frozen history once persisted).
struct ShiftDigestArtifactsView: View {
    let snapshot: ShiftDigestArtifactsSnapshot

    var body: some View {
        VStack(spacing: Theme.spacing) {
            if !snapshot.doses.isEmpty {
                section(
                    title: "Medications",
                    systemImage: "pills.fill"
                ) {
                    ForEach(snapshot.doses) { dose in
                        DoseArtifactRow(dose: dose)
                    }
                }
            }

            if !snapshot.appointments.isEmpty {
                section(
                    title: "Appointments",
                    systemImage: "calendar"
                ) {
                    ForEach(snapshot.appointments) { appointment in
                        AppointmentArtifactRow(appointment: appointment)
                    }
                }
            }

            if !snapshot.vitals.isEmpty {
                section(
                    title: "Vitals",
                    systemImage: "heart.text.square"
                ) {
                    ForEach(snapshot.vitals) { vital in
                        VitalArtifactRow(vital: vital)
                    }
                }
            }

            if !snapshot.journal.isEmpty {
                section(
                    title: "Journal",
                    systemImage: "book.closed"
                ) {
                    ForEach(snapshot.journal) { entry in
                        JournalArtifactRow(entry: entry)
                    }
                }
            }
        }
    }

    private func section(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ccPrimary)
            VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                content()
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }
}

// MARK: - Rows

private struct DoseArtifactRow: View {
    let dose: ShiftDigestArtifactsSnapshot.DoseSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(dose.medicationName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ccText)
                Spacer()
                StatusBadge(text: dose.status.capitalized, tone: statusTone)
            }
            HStack(spacing: Theme.tightSpacing) {
                if let dosage = dose.dosage, !dosage.isEmpty {
                    Text(dosage)
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                Text(dose.scheduledAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
                if let takenAt = dose.takenAt {
                    Text("• Taken \(takenAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
        }
    }

    private var statusTone: StatusBadge.Tone {
        switch dose.status.lowercased() {
        case "taken": .success
        case "skipped", "missed": .danger
        case "late": .warning
        default: .neutral
        }
    }
}

private struct AppointmentArtifactRow: View {
    let appointment: ShiftDigestArtifactsSnapshot.AppointmentSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(appointment.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ccText)
                Spacer()
                if let status = appointment.status {
                    StatusBadge(
                        text: status.capitalized,
                        tone: status.lowercased() == "attended" ? .success : .neutral
                    )
                }
            }
            Text(
                "\(appointment.startsAt.formatted(date: .abbreviated, time: .shortened)) • \(appointment.durationMinutes) min"
            )
            .font(.caption)
            .foregroundStyle(Color.ccSecondary)
        }
    }
}

private struct VitalArtifactRow: View {
    let vital: ShiftDigestArtifactsSnapshot.VitalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(vital.kind)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.ccText)
                Spacer()
                Text("\(vital.value)\(vital.unit.map { " \($0)" } ?? "")")
                    .font(.body)
                    .foregroundStyle(Color.ccText)
            }
            Text(vital.recordedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(Color.ccSecondary)
        }
    }
}

private struct JournalArtifactRow: View {
    let entry: ShiftDigestArtifactsSnapshot.JournalSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if let mood = entry.mood {
                    Text(mood)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.ccText)
                }
                Spacer()
                Text(entry.recordedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
            Text(entry.summary)
                .font(.body)
                .foregroundStyle(Color.ccText)
        }
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    enum Tone {
        case success
        case warning
        case danger
        case neutral
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch tone {
        case .success: Color.ccPrimary.opacity(0.16)
        case .warning: Color.orange.opacity(0.18)
        case .danger: Color.ccDanger.opacity(0.18)
        case .neutral: Color.ccSecondary.opacity(0.18)
        }
    }

    private var foreground: Color {
        switch tone {
        case .success: Color.ccPrimary
        case .warning: Color.orange
        case .danger: Color.ccDanger
        case .neutral: Color.ccSecondary
        }
    }
}
