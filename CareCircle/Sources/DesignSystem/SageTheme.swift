import SwiftUI

// MARK: - Theme

enum Theme {
    static let cornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 16
    static let spacing: CGFloat = 16
    static let tightSpacing: CGFloat = 8
    static let looseSpacing: CGFloat = 24
}

// MARK: - Color + CareCircle palette

extension Color {
    /// Sage green — primary brand color per spec C1.
    static let ccPrimary = Color(red: 0.498, green: 0.624, blue: 0.541)

    /// Warm cream — app background.
    static let ccBackground = Color(red: 0.969, green: 0.957, blue: 0.929)

    /// Deep navy — primary text.
    static let ccText = Color(red: 0.118, green: 0.196, blue: 0.290)

    /// Muted sage — secondary text and chrome.
    static let ccSecondary = Color(red: 0.435, green: 0.518, blue: 0.475)

    /// Warm clay — destructive / error.
    static let ccDanger = Color(red: 0.741, green: 0.349, blue: 0.298)

    /// Subtle surface tint over the background.
    static let ccSurface = Color(red: 0.949, green: 0.933, blue: 0.894)
}
