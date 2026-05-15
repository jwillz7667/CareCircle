import SwiftUI

// MARK: - BrandLogo

/// CareCircle's brand mark on a white disc. The white background is
/// load-bearing: the icon artwork is colored and would clash with the
/// app's tinted backgrounds (Color.ccBackground in particular) without
/// it. Use `size` to scale the whole assembly — the inner artwork
/// inset and shadow scale proportionally so the proportions hold at
/// 28pt (toolbar) through 140pt (splash).
struct BrandLogo: View {
    var size: CGFloat = 96

    /// Fraction of the outer diameter occupied by the logo artwork.
    /// 0.78 leaves a clean halo of white around the icon without
    /// shrinking the mark so much that it looks lost inside the disc.
    private let artworkRatio: CGFloat = 0.78

    var body: some View {
        // SwiftUI.Circle qualified per the SwiftData/SwiftUI Circle
        // name collision noted in CLAUDE.md gotchas.
        SwiftUI.Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.08), radius: size * 0.05, y: size * 0.015)
            .overlay {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * artworkRatio, height: size * artworkRatio)
                    .clipShape(.circle)
            }
            .accessibilityHidden(true)
    }
}

#Preview("Logo sizes") {
    VStack(spacing: 24) {
        BrandLogo(size: 28)
        BrandLogo(size: 56)
        BrandLogo(size: 96)
        BrandLogo(size: 140)
    }
    .padding(40)
    .background(Color.ccBackground)
}
