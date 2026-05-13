import SwiftUI

// MARK: - CareMinuteRowView

/// Compact list row for a single `CareMinuteEntry`. Mirrors the layout
/// used in the calendar-week view and the export preview.
struct CareMinuteRowView: View {
    let entry: CareMinuteEntry
    let showsCaregiver: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            ZStack {
                Color.ccBackground.clipShape(.circle)
                Image(systemName: entry.serviceCode.symbol)
                    .foregroundStyle(Color.ccPrimary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.serviceCode.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Spacer()
                    Text(String(format: "%.2f h", entry.durationHours))
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(Color.ccText)
                }
                Text(timeRange)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.ccSecondary)

                if showsCaregiver, !entry.caregiverDisplayName.isEmpty {
                    Text(entry.caregiverDisplayName)
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                }

                if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !notes.isEmpty
                {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(Color.ccSecondary)
                        .lineLimit(2)
                }

                if entry.exportedAt != nil {
                    Label("Exported", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.ccPrimary)
                }
            }
        }
        .padding(Theme.spacing)
        .contentShape(Rectangle())
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: entry.startedAt)) – \(formatter.string(from: entry.endedAt))"
    }
}
