import SwiftUI

// MARK: - CircleHero

struct CircleHero: View {
    let circleName: String
    let recipient: CareRecipient?

    var body: some View {
        VStack(alignment: .center, spacing: Theme.spacing) {
            PhotoCircleView(imageData: recipient?.photoData, diameter: 112)

            VStack(spacing: 4) {
                if let recipient {
                    Text(recipient.fullName)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                        .multilineTextAlignment(.center)

                    if let age = recipient.ageYears {
                        Text(ageLabel(for: age))
                            .font(.subheadline)
                            .foregroundStyle(Color.ccSecondary)
                    }
                }

                Text(circleName)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.ccSecondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity)
        .background(Color.ccSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    private func ageLabel(for age: Int) -> String {
        age == 1 ? "1 year old" : "\(age) years old"
    }
}
