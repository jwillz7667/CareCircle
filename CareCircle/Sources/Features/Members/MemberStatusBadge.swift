import SwiftUI

// MARK: - MemberStatusBadge

struct MemberStatusBadge: View {
    let status: MemberStatus

    var body: some View {
        HStack(spacing: 4) {
            SwiftUI.Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.ccSurface)
        .foregroundStyle(textColor)
        .clipShape(Capsule())
    }

    private var dotColor: Color {
        switch status {
        case .active: Color.ccPrimary
        case .invited: Color.orange
        case .removed: Color.ccSecondary.opacity(0.6)
        }
    }

    private var textColor: Color {
        switch status {
        case .active: Color.ccPrimary
        case .invited: Color.orange
        case .removed: Color.ccSecondary
        }
    }
}
