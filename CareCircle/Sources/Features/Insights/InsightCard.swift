import SwiftUI

// MARK: - InsightCard

/// Single insight surface used inside `InsightsView` and the Today
/// dashboard's Pulse card. The same card is also reused in the apply
/// CTA target so the caregiver can see the observation that prompted
/// the navigation.
struct InsightCard: View {
    let insight: Insight
    var compact = false
    var onDismiss: (() -> Void)?
    var onApply: (() -> Void)?

    private var severity: InsightSeverity {
        insight.severity
    }

    private var kind: InsightKind {
        insight.kind
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            severityStripe
            VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                header
                Text(insight.body)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
                    .lineLimit(compact ? 2 : nil)
                if !compact {
                    actionRow
                }
            }
        }
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }

    private var header: some View {
        HStack(spacing: Theme.tightSpacing) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(insight.title)
                .font(.headline)
                .foregroundStyle(Color.ccText)
                .frame(maxWidth: .infinity, alignment: .leading)
            severityPill
        }
    }

    private var severityStripe: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(tint)
            .frame(width: 4)
            .frame(maxHeight: .infinity)
    }

    private var severityPill: some View {
        Text(severityLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.16)))
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var actionRow: some View {
        if onDismiss != nil || onApply != nil {
            HStack(spacing: Theme.spacing) {
                Spacer(minLength: 0)
                if let onDismiss {
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.bordered)
                        .tint(Color.ccSecondary)
                        .accessibilityHint("Hide this insight permanently.")
                }
                if let onApply {
                    Button("Open") {
                        onApply()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .accessibilityHint("Open the related item to act on this insight.")
                }
            }
        }
    }

    private var severityLabel: String {
        switch severity {
        case .warning: "Heads up"
        case .suggestion: "Suggestion"
        case .info: "Info"
        }
    }

    private var tint: Color {
        switch severity {
        case .warning: Color.ccDanger
        case .suggestion: Color.ccPrimary
        case .info: Color.ccSecondary
        }
    }
}
