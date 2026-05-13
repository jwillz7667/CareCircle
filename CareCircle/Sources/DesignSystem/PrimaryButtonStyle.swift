import SwiftUI

// MARK: - PrimaryButtonStyle

struct PrimaryButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, Theme.spacing)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        switch prominence {
        case .primary: Color.ccPrimary
        case .secondary: Color.ccSurface
        }
    }

    private var foreground: Color {
        switch prominence {
        case .primary: .white
        case .secondary: Color.ccText
        }
    }
}

// MARK: - ButtonStyle + PrimaryButtonStyle conveniences

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var ccPrimary: PrimaryButtonStyle {
        PrimaryButtonStyle(prominence: .primary)
    }

    static var ccSecondary: PrimaryButtonStyle {
        PrimaryButtonStyle(prominence: .secondary)
    }
}
