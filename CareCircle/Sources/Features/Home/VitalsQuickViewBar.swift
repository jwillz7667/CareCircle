import SwiftUI

// MARK: - VitalsQuickViewBar

/// Compact at-a-glance vitals strip rendered on the Home dashboard.
/// Shows the latest reading for the four highest-signal vitals (HR,
/// SpO₂, BP, Temp), each pulled from the same SwiftData store that
/// HealthKit imports land in. The whole strip is a button — tapping
/// any cell jumps the user to the Vitals tab, where they get the full
/// PulseDashboard with hero card, anomaly callouts, sparklines, and
/// bedside monitor.
///
/// When a vital has no reading yet, its cell renders an em-dash so the
/// layout doesn't collapse and the user can still see which signals
/// are tracked.
struct VitalsQuickViewBar: View {
    let circle: Circle?
    let onTap: () -> Void

    private var summaries: [VitalsAnalytics.KindSummary] {
        guard let circle else { return [] }
        return VitalsAnalytics.summarize(vitals: circle.vitals)
    }

    private var mostRecentTimestamp: Date? {
        summaries.compactMap(\.latest?.recordedAt).max()
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                header
                HStack(spacing: 0) {
                    cell(
                        systemName: "heart.fill",
                        tint: Color.ccDanger,
                        value: hrText,
                        label: "HR"
                    )
                    divider
                    cell(
                        systemName: "lungs.fill",
                        tint: Color.cyan,
                        value: spo2Text,
                        label: "SpO₂"
                    )
                    divider
                    cell(
                        systemName: "waveform.path.ecg",
                        tint: Color.orange,
                        value: bpText,
                        label: "BP"
                    )
                    divider
                    cell(
                        systemName: "thermometer.medium",
                        tint: Color.pink,
                        value: tempText,
                        label: "Temp"
                    )
                }
            }
            .padding(.vertical, Theme.tightSpacing + 2)
            .padding(.horizontal, Theme.tightSpacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .fill(Color.ccSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .stroke(Color.ccText.opacity(0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the Vitals tab")
        .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ccPrimary)
            Text("Vitals")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ccText)
            if let timestamp = mostRecentTimestamp {
                Text("· \(VitalFormatting.relativeRecordedAt(timestamp))")
                    .font(.caption2)
                    .foregroundStyle(Color.ccSecondary)
            } else {
                Text("· no readings yet")
                    .font(.caption2)
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.ccSecondary)
        }
        .padding(.horizontal, Theme.tightSpacing - 2)
    }

    private func cell(
        systemName: String,
        tint: Color,
        value: String,
        label: String
    )
        -> some View
    {
        VStack(spacing: 2) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ccText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(.caption2, weight: .medium))
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.ccText.opacity(0.07))
            .frame(width: 1, height: 36)
    }

    private func latest(_ kind: VitalKind) -> Double? {
        summaries.first(where: { $0.kind == kind })?.latest?.value
    }

    private var hrText: String {
        guard let value = latest(.heartRate) else { return "—" }
        return "\(Int(value.rounded()))"
    }

    private var spo2Text: String {
        guard let value = latest(.oxygenSaturation) else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var bpText: String {
        guard let systolic = latest(.bloodPressureSystolic),
              let diastolic = latest(.bloodPressureDiastolic)
        else {
            return "—"
        }
        return "\(Int(systolic.rounded()))/\(Int(diastolic.rounded()))"
    }

    private var tempText: String {
        guard let value = latest(.bodyTemperature) else { return "—" }
        return String(format: "%.1f°", value)
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let value = latest(.heartRate) {
            parts.append("Heart rate \(Int(value.rounded())) beats per minute")
        }
        if let value = latest(.oxygenSaturation) {
            parts.append("Oxygen saturation \(Int(value.rounded())) percent")
        }
        if let systolic = latest(.bloodPressureSystolic),
           let diastolic = latest(.bloodPressureDiastolic)
        {
            parts.append(
                "Blood pressure \(Int(systolic.rounded())) over \(Int(diastolic.rounded()))"
            )
        }
        if let value = latest(.bodyTemperature) {
            parts.append("Temperature \(String(format: "%.1f", value)) degrees")
        }
        if parts.isEmpty {
            return "Vitals quick view, no readings yet."
        }
        return "Vitals quick view. " + parts.joined(separator: ". ")
    }
}
