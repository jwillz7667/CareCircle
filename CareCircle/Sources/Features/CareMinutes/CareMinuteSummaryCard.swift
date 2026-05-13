import SwiftUI

// MARK: - CareMinuteSummaryCard

/// Per-week rollup card: big total at top, optional per-service-code
/// breakdown below. Reused by the list view and could be reused for a
/// "this week" widget down the road.
struct CareMinuteSummaryCard: View {
    let entries: [CareMinuteEntry]
    let scopeLabel: String?

    private var totalsByCode: [(code: HCBSServiceCode, entries: [CareMinuteEntry])] {
        CareMinuteService.groupedByServiceCode(entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(CareMinuteService.totalHoursFormatted(in: entries))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ccText)
                Text("this week")
                    .font(.subheadline)
                    .foregroundStyle(Color.ccSecondary)
                Spacer()
                if let scopeLabel {
                    Text(scopeLabel)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.ccSurface)
                        .foregroundStyle(Color.ccSecondary)
                        .clipShape(Capsule())
                }
            }

            if !totalsByCode.isEmpty {
                Divider()
                ForEach(totalsByCode, id: \.code) { row in
                    HStack(spacing: Theme.tightSpacing) {
                        Image(systemName: row.code.symbol)
                            .frame(width: 22)
                            .foregroundStyle(Color.ccPrimary)
                        Text(row.code.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Color.ccText)
                        Spacer()
                        Text(CareMinuteService.totalHoursFormatted(in: row.entries))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.ccSecondary)
                    }
                }
            }
        }
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }
}
