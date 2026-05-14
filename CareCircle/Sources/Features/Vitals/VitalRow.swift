import SwiftData
import SwiftUI

// MARK: - VitalRow

/// One row in the vitals list. Renders the kind icon in a tinted
/// circle, the formatted value + unit as the primary text, and a
/// secondary line with the relative timestamp, source (manual /
/// Apple Health), and recorder display name when available.
struct VitalRow: View {
    let vital: Vital
    let recorderDisplayName: String?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            iconBubble
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(vital.kind.shortName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.ccSecondary)
                    sourceBadge
                }
                Text(VitalFormatting.formattedValueWithUnit(vital))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(secondaryLine)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccSurface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconBubble: some View {
        ZStack {
            SwiftUI.Circle()
                .fill(vital.kind.tintColor.opacity(0.18))
            Image(systemName: vital.kind.systemImageName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(vital.kind.tintColor)
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if vital.source == .healthkit {
            Label("Health", systemImage: "heart.text.square.fill")
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(Color.ccPrimary)
                .accessibilityLabel("Imported from Apple Health")
        }
    }

    private var secondaryLine: String {
        let relative = VitalFormatting.relativeRecordedAt(vital.recordedAt)
        if let recorderDisplayName, !recorderDisplayName.isEmpty {
            return "\(relative) · \(recorderDisplayName)"
        }
        if vital.source == .healthkit {
            return "\(relative) · Apple Health"
        }
        return relative
    }

    private var accessibilityLabel: String {
        let value = VitalFormatting.formattedValueWithUnit(vital)
        let when = VitalFormatting.absoluteRecordedAt(vital.recordedAt)
        return "\(vital.kind.displayName), \(value), recorded \(when)"
    }
}
