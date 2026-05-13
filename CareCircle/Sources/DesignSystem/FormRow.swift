import SwiftUI

// MARK: - FormRow

struct FormRow<Content: View>: View {
    let label: String
    let hint: String?
    let content: Content

    init(_ label: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ccSecondary)

            content

            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
        .padding(.vertical, Theme.tightSpacing / 2)
    }
}
