import SwiftUI

// MARK: - MedicationRowView

/// Compact row used in the medications list. Shows the form-icon glyph, name,
/// dose, and a short "Next dose" / "As needed" / "Discontinued" status string.
struct MedicationRowView: View {
    let medication: Medication

    private var nextDoseDescription: String {
        switch medication.status {
        case .discontinued:
            return "Discontinued"
        case .asNeeded:
            return "As needed"
        case .active:
            if medication.schedule.frequency == .asNeeded {
                return "As needed"
            }
            if let next = medication.schedule.upcomingOccurrences(after: Date(), limit: 1).first {
                let relative = next.formatted(.relative(presentation: .named))
                let exact = next.formatted(date: .omitted, time: .shortened)
                return "Next \(relative) at \(exact)"
            }
            return "No upcoming doses"
        }
    }

    var body: some View {
        HStack(spacing: Theme.spacing) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(medication.name.isEmpty ? "Untitled medication" : medication.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ccText)

                HStack(spacing: 6) {
                    Text(medication.dosage)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                    if !medication.dosage.isEmpty {
                        Text("·").foregroundStyle(Color.ccSecondary)
                    }
                    Text(medication.form.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.ccSecondary)
                }

                Text(nextDoseDescription)
                    .font(.footnote)
                    .foregroundStyle(Color.ccPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.tightSpacing / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.ccSurface)
                .frame(width: 44, height: 44)
            Image(systemName: medication.form.systemImageName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.ccPrimary)
                .accessibilityHidden(true)
        }
    }

    private var accessibilityDescription: String {
        "\(medication.name), \(medication.dosage), \(medication.form.displayName). \(nextDoseDescription)."
    }
}
