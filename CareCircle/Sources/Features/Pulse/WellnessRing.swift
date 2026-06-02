import SwiftUI

// MARK: - WellnessRing

/// Composite "today's wellbeing" ring rendered as an iOS-26-style
/// liquid-glass dial. Drives the score from `VitalsAnalytics`'s
/// composite — penalty-based, heuristic, *not* medical advice (and the
/// hero strip always reflects that with the trailing disclaimer).
///
/// The ring is animated on appear / score change with a spring so the
/// fill feels like a wearable. Tap forwards to the monitor view; the
/// surrounding host owns navigation.
struct WellnessRing: View {
    let score: Int?
    let trendLabel: String?
    let subtitle: String

    @State private var animatedScore: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        min(100, max(0, Double(score ?? 0)))
    }

    var body: some View {
        HStack(spacing: Theme.spacing) {
            ZStack {
                background
                fill
                centerLabel
            }
            .frame(width: 120, height: 120)
            .onAppear { animateTo(clamped) }
            .onChange(of: clamped) { _, newValue in animateTo(newValue) }

            VStack(alignment: .leading, spacing: 6) {
                Text("Today's wellbeing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                    .multilineTextAlignment(.leading)
                if let trendLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption.weight(.semibold))
                        Text(trendLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(Color.ccPrimary)
                    .background(Color.ccPrimary.opacity(0.12), in: Capsule())
                }
                Text("Heuristic indicator — not medical advice.")
                    .font(.system(.caption2))
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccSurface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(score == nil
            ? "Wellbeing score not yet available."
            : "Today's wellbeing score: \(score ?? 0) out of 100. \(subtitle)")
    }

    private var background: some View {
        SwiftUI.Circle()
            .stroke(Color.ccPrimary.opacity(0.12), lineWidth: 12)
    }

    private var fill: some View {
        SwiftUI.Circle()
            .trim(from: 0, to: animatedScore / 100)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.ccDanger.opacity(0.9),
                        Color.orange,
                        Color.yellow,
                        Color.green,
                        Color.ccPrimary,
                    ]),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: 12, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: ringColor.opacity(0.35), radius: 6)
    }

    private var centerLabel: some View {
        VStack(spacing: 0) {
            if let score {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.ccText)
                Text("of 100")
                    .font(.caption2)
                    .foregroundStyle(Color.ccSecondary)
            } else {
                Image(systemName: "ellipsis")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ccSecondary)
                Text("syncing")
                    .font(.caption2)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
    }

    private var ringColor: Color {
        switch clamped {
        case 80...: Color.ccPrimary
        case 60 ..< 80: Color.green
        case 40 ..< 60: Color.orange
        default: Color.ccDanger
        }
    }

    private func animateTo(_ value: Double) {
        withAnimation(Motion.respecting(reduceMotion, .spring(response: 1.1, dampingFraction: 0.78))) {
            animatedScore = value
        }
    }
}
