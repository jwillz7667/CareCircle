import SwiftUI

// MARK: - MedicationDisclaimerFooter

/// Inline variant of the spec §5.6 disclaimer for medication screens.
/// `DisclaimerFooter` is the chrome variant pinned to the bottom of a tab;
/// this one renders mid-flow inside a Form/Section footer.
struct MedicationDisclaimerFooter: View {
    var body: some View {
        Label(
            "Not medical advice — consult your healthcare provider.",
            systemImage: "info.circle"
        )
        .font(.footnote)
        .foregroundStyle(Color.ccSecondary)
        .padding(Theme.tightSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Medical disclaimer: Not medical advice. Consult your healthcare provider."
        )
    }
}
