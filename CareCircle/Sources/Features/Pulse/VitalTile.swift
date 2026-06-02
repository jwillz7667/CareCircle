import Charts
import SwiftUI

// MARK: - VitalTile

/// Compact "now" tile for one `VitalKind` in the Pulse monitor grid.
/// Each tile shows the kind glyph, current value + unit, a 14-day
/// sparkline driven by `VitalsAnalytics`, and a trend / anomaly chip.
struct VitalTile: View {
    let summary: VitalsAnalytics.KindSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            valueRow
            sparkline
            footerChip
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(tileBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(summary.isAnomalous ? Color.ccDanger : Color.clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: summary.kind.systemImageName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(summary.kind.tintColor)
            Text(summary.kind.shortName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Spacer(minLength: 0)
            if summary.isAnomalous {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.ccDanger)
                    .accessibilityLabel("Anomalous reading")
            }
        }
    }

    private var valueRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            if let latest = summary.latest {
                Text(VitalFormatting.formattedValue(latest.value, kind: summary.kind))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.ccText)
                Text(latest.unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.ccSecondary)
            } else {
                Text("—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        if summary.sparkline.count >= 2 {
            Chart(summary.sparkline) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(summary.kind.tintColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            summary.kind.tintColor.opacity(0.30),
                            summary.kind.tintColor.opacity(0.02),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 28)
        } else {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 28)
        }
    }

    private var footerChip: some View {
        HStack(spacing: 4) {
            Image(systemName: summary.trend.systemImage)
                .font(.system(.caption2, weight: .bold))
            Text(trendLabel)
                .font(.system(.caption2, weight: .semibold))
                .monospacedDigit()
            Spacer(minLength: 0)
            if let latest = summary.latest {
                Text(VitalFormatting.relativeRecordedAt(latest.recordedAt))
                    .font(.system(.caption2))
                    .foregroundStyle(Color.ccSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(trendColor)
    }

    private var trendLabel: String {
        if let delta = summary.trendDeltaPercent, summary.trend != .unknown {
            let sign = delta > 0 ? "+" : ""
            return "\(sign)\(String(format: "%.0f", delta))% 14d"
        }
        return "baseline"
    }

    private var trendColor: Color {
        if summary.isAnomalous { return Color.ccDanger }
        switch summary.trend {
        case .rising: return summary.kind == .stepCount || summary.kind == .sleepHours
            ? Color.ccPrimary : Color.ccDanger.opacity(0.85)
        case .falling: return summary.kind == .stepCount || summary.kind == .sleepHours
            ? Color.ccDanger.opacity(0.85) : Color.ccPrimary
        case .flat, .unknown: return Color.ccSecondary
        }
    }

    private var tileBackground: Color {
        summary.isAnomalous ? Color.ccDanger.opacity(0.06) : Color.ccSurface
    }

    private var accessibilityLabel: String {
        guard let latest = summary.latest else {
            return "\(summary.kind.displayName), no readings yet."
        }
        var label = "\(summary.kind.displayName), \(VitalFormatting.formattedValue(latest.value, kind: summary.kind)) \(latest.unit)"
        if summary.isAnomalous { label += ", anomalous reading flagged" }
        return label
    }
}
