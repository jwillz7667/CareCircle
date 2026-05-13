import SwiftUI

// MARK: - MemberRoleBadge

struct MemberRoleBadge: View {
    let role: MemberRole

    var body: some View {
        Text(role.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch role {
        case .owner: Color.ccPrimary.opacity(0.18)
        case .careRecipient: Color.ccDanger.opacity(0.15)
        default: Color.ccSecondary.opacity(0.18)
        }
    }

    private var foreground: Color {
        switch role {
        case .owner: Color.ccPrimary
        case .careRecipient: Color.ccDanger
        default: Color.ccSecondary
        }
    }
}
