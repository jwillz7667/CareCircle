import SwiftUI

// MARK: - CaregiverShareRing

/// A single member's share of the Circle's care load, rendered as a
/// thin filled ring with an initial inside. The fill arc represents what
/// fraction of the total score this caregiver contributed; the color
/// shifts from danger (≤ 10 %) through warning (≤ 25 %) to primary
/// (above) so a glance answers "is this person doing their share?"
struct CaregiverShareRing: View {
    let displayName: String
    let share: Double
    let size: CGFloat

    @State private var animatedShare: Double = 0

    init(displayName: String, share: Double, size: CGFloat = 56) {
        self.displayName = displayName
        self.share = share
        self.size = size
    }

    private var clamped: Double {
        min(1, max(0, share))
    }

    private var ringColor: Color {
        switch clamped {
        case 0.25...: Color.ccPrimary
        case 0.1 ..< 0.25: Color.orange
        default: Color.ccDanger
        }
    }

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let chars = parts.compactMap(\.first).map(String.init)
        let joined = chars.joined()
        return joined.isEmpty ? "?" : joined.uppercased()
    }

    var body: some View {
        ZStack {
            SwiftUI.Circle()
                .stroke(ringColor.opacity(0.15), lineWidth: 5)

            SwiftUI.Circle()
                .trim(from: 0, to: animatedShare)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(initials)
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ccText)
        }
        .frame(width: size, height: size)
        .onAppear { animateTo(clamped) }
        .onChange(of: clamped) { _, value in animateTo(value) }
        .accessibilityHidden(true)
    }

    private func animateTo(_ value: Double) {
        withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) {
            animatedShare = value
        }
    }
}
