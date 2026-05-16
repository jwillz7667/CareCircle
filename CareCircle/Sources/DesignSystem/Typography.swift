import SwiftUI

/// Semantic typography tokens. Every token is built on a system text
/// style so Dynamic Type scaling works to AX5 without per-screen tuning.
/// Pair with `.lineSpacing(Typography.lineSpacingDefault)` where multi-
/// line readability matters.
extension Font {
    /// Brand-prefixed nest matching the `Color.cc*` token scheme so call
    /// sites read as `Font.CC.titleLarge`. Two-letter name is the brand
    /// shorthand — the swiftlint waiver is intentional.
    enum CC { // swiftlint:disable:this type_name
        /// 34pt @ default. Reserved for one-per-screen hero text.
        static let displayLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)

        /// 28pt @ default. NavigationStack large-title equivalent.
        static let titleLarge = Font.system(.title, design: .rounded, weight: .semibold)

        /// 22pt @ default. Card titles, section opens.
        static let titleMedium = Font.system(.title2, design: .rounded, weight: .semibold)

        /// 20pt @ default. Sub-section titles inside a card.
        static let titleSmall = Font.system(.title3, design: .rounded, weight: .medium)

        /// 17pt @ default, weighted. Use over `body` when the line
        /// carries scanning weight (row primary, list-section header).
        static let headline = Font.system(.headline, design: .default, weight: .semibold)

        /// 17pt @ default. Default reading text.
        static let body = Font.system(.body, design: .default, weight: .regular)

        /// 17pt @ default. Body text that needs to read as primary
        /// among siblings (selected row, emphasis run).
        static let bodyEmphasized = Font.system(.body, design: .default, weight: .medium)

        /// 15pt @ default. Supporting text under a row.
        static let caption = Font.system(.subheadline, design: .default, weight: .regular)

        /// 13pt @ default. Metadata, timestamps, tags.
        static let captionSmall = Font.system(.caption, design: .default, weight: .regular)

        /// 13pt @ default, weighted. Use for chip labels, badge text.
        static let label = Font.system(.footnote, design: .default, weight: .medium)

        /// 28pt @ default, monospaced digits. For numeric vitals,
        /// readings, countdowns — keeps columns aligned.
        static let numericDisplay = Font.system(.title, design: .rounded, weight: .semibold)
            .monospacedDigit()
    }
}

enum Typography {
    /// Line spacing for multi-line body text. Tuned to feel calm at
    /// default size and stay readable at AX5.
    static let lineSpacingDefault: CGFloat = 3
}
