import SwiftUI

// MARK: - BrandLogo

/// CareCircle's brand mark. The artwork is presented at its full
/// rendered size — `size` controls both the bounding box and the
/// artwork inside it (the artwork fills the box). Use `size` to scale
/// from 28pt (toolbar) through 140pt (splash).
struct BrandLogo: View {
    var size: CGFloat = 96

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
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
