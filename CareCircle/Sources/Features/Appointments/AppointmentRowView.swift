import SwiftUI

// MARK: - AppointmentRowView

/// Compact row used in the appointments list and the Today timeline. Shows
/// the title, start time, location, and transport-responsible chip when set.
struct AppointmentRowView: View {
    let appointment: Appointment
    var showsDate = false

    var body: some View {
        HStack(spacing: Theme.spacing) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)

                Text(timeDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.ccSecondary)

                if let location = appointment.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !location.isEmpty
                {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }

                if let transport = appointment.transportResponsibleDisplayName?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !transport.isEmpty
                {
                    Label("\(transport) driving", systemImage: "car.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.ccPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if appointment.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.ccPrimary)
                    .accessibilityLabel("Completed")
            }
        }
        .padding(.vertical, Theme.tightSpacing / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var displayTitle: String {
        let trimmed = appointment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled appointment" : trimmed
    }

    private var timeDescription: String {
        let start = appointment.startsAt
        let timeString = start.formatted(date: .omitted, time: .shortened)
        if showsDate {
            return "\(start.formatted(date: .abbreviated, time: .omitted)) · \(timeString)"
        }
        return timeString
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.ccSurface)
                .frame(width: 44, height: 44)
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ccPrimary)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = [displayTitle, timeDescription]
        if let provider = appointment.provider?.trimmingCharacters(in: .whitespacesAndNewlines),
           !provider.isEmpty
        {
            parts.append("with \(provider)")
        }
        if appointment.isCompleted {
            parts.append("completed")
        }
        return parts.joined(separator: ", ")
    }
}
