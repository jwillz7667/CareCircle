import SwiftUI
import UIKit

/// Adaptive semantic color tokens. These resolve per trait collection,
/// so dark mode and high-contrast accessibility settings work without
/// the per-view `.preferredColorScheme(.light)` pin currently set in
/// `CareCircleApp`. The legacy `Color.ccPrimary` / `Color.ccBackground`
/// constants in `SageTheme.swift` remain so existing screens keep
/// working — migrate to these tokens as screens get touched.
///
/// Naming follows role, not hue: `backgroundPrimary` will be cream in
/// light, deep slate in dark, true white/black in high-contrast.
extension Color {
    /// App background. Cream / deep slate / pure black|white.
    static let ccBackgroundPrimary = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark ? .black : .white
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.090, blue: 0.106, alpha: 1.0)
            : UIColor(red: 0.969, green: 0.957, blue: 0.929, alpha: 1.0)
    })

    /// Surface that sits one layer above the background (cards, rows).
    static let ccSurfacePrimary = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1.0) : UIColor(
                white: 0.96,
                alpha: 1.0
            )
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.118, green: 0.137, blue: 0.157, alpha: 1.0)
            : UIColor(red: 0.949, green: 0.933, blue: 0.894, alpha: 1.0)
    })

    /// Surface elevated above the primary surface (modal sheets,
    /// sticky headers).
    static let ccSurfaceElevated = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark ? UIColor(white: 0.18, alpha: 1.0) : UIColor.white
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.157, green: 0.180, blue: 0.204, alpha: 1.0)
            : UIColor.white
    })

    /// Primary text. Deep navy in light, near-white in dark.
    static let ccTextPrimary = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark ? .white : .black
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.949, green: 0.953, blue: 0.957, alpha: 1.0)
            : UIColor(red: 0.118, green: 0.196, blue: 0.290, alpha: 1.0)
    })

    /// Secondary / supporting text. Holds 4.5:1 against both
    /// `ccBackgroundPrimary` and `ccSurfacePrimary` in either mode.
    static let ccTextSecondary = Color(uiColor: UIColor { traits in
        if traits.accessibilityContrast == .high {
            return traits.userInterfaceStyle == .dark ? UIColor(white: 0.85, alpha: 1.0) : UIColor(
                white: 0.20,
                alpha: 1.0
            )
        }
        return traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.706, green: 0.737, blue: 0.722, alpha: 1.0)
            : UIColor(red: 0.355, green: 0.435, blue: 0.395, alpha: 1.0)
    })

    /// Brand accent. Forest green in light, brighter sage in dark.
    static let ccAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.388, green: 0.682, blue: 0.557, alpha: 1.0)
            : UIColor(red: 0.176, green: 0.416, blue: 0.310, alpha: 1.0)
    })

    /// Soft accent fill for tinted chips, badges, selected rows.
    static let ccAccentSoft = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.176, green: 0.416, blue: 0.310, alpha: 0.30)
            : UIColor(red: 0.176, green: 0.416, blue: 0.310, alpha: 0.12)
    })

    /// Subtle hairline / divider. 1pt at this color reads cleanly in
    /// both modes.
    static let ccBorderHairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.10)
            : UIColor(red: 0.118, green: 0.196, blue: 0.290, alpha: 0.10)
    })

    /// Status: positive (within range, recently confirmed).
    static let ccStatusPositive = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.420, green: 0.749, blue: 0.482, alpha: 1.0)
            : UIColor(red: 0.196, green: 0.541, blue: 0.310, alpha: 1.0)
    })

    /// Status: attention needed (creeping trend, soon-due dose).
    static let ccStatusAttention = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.957, green: 0.706, blue: 0.380, alpha: 1.0)
            : UIColor(red: 0.804, green: 0.514, blue: 0.176, alpha: 1.0)
    })

    /// Status: critical (missed life-critical dose, red-zone vital).
    static let ccStatusCritical = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.957, green: 0.412, blue: 0.380, alpha: 1.0)
            : UIColor(red: 0.741, green: 0.349, blue: 0.298, alpha: 1.0)
    })
}

/// Spacing scale. Use these instead of magic numbers so density
/// stays consistent and a future density toggle remains feasible.
enum Spacing {
    /// 4pt — between glyphs that share a row.
    static let xxs: CGFloat = 4
    /// 8pt — inside a chip / between an icon and its label.
    static let xs: CGFloat = 8
    /// 12pt — tight rows.
    static let s: CGFloat = 12
    /// 16pt — default row + card inner padding.
    static let m: CGFloat = 16
    /// 24pt — between cards.
    static let l: CGFloat = 24
    /// 32pt — section breaks.
    static let xl: CGFloat = 32
    /// 48pt — between large hero blocks.
    static let xxl: CGFloat = 48
}

/// Corner radius scale. Tied to a single visual language: gently
/// rounded everywhere, never sharp.
enum Radius {
    static let chip: CGFloat = 10
    static let row: CGFloat = 12
    static let card: CGFloat = 16
    static let sheet: CGFloat = 24
}
