import SwiftUI

// MARK: - DisclaimerFooter

struct DisclaimerFooter: View {
    var body: some View {
        Text("Not medical advice — consult your healthcare provider.")
            .font(.footnote)
            .foregroundStyle(Color.ccSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.tightSpacing)
            .frame(maxWidth: .infinity)
            .background(Color.ccSurface)
            .accessibilityLabel("Medical disclaimer: Not medical advice. Consult your healthcare provider.")
    }
}

#Preview {
    DisclaimerFooter()
}
