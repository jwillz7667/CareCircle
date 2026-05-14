import SwiftUI

// MARK: - PillIdentifierResultView

/// Renders an identified pill (post-openFDA lookup) with ingredient
/// overlap rows and the "Add to medications" CTA. Embedded inside the
/// `PillIdentifierView` coordinator — never presented stand-alone.
struct PillIdentifierResultView: View {
    let result: PillIdentificationResult
    let interactions: [InteractionChecker.Match]
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                header
                summary
                if !result.activeIngredients.isEmpty {
                    ingredients
                }
                if !interactions.isEmpty {
                    interactionsSection
                }
                actions
                disclaimer
            }
            .padding(Theme.spacing)
        }
        .background(Color.ccBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text(result.displayName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Text("NDC \(result.matchedNDC)")
                .font(.footnote.monospaced())
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            if !result.genericNames.isEmpty {
                detailRow(title: "Generic", value: result.genericNames.joined(separator: ", "))
            }
            if !result.dosageForms.isEmpty {
                detailRow(title: "Form", value: result.dosageForms.joined(separator: ", ").titlecased())
            }
            if !result.routes.isEmpty {
                detailRow(title: "Route", value: result.routes.joined(separator: ", ").titlecased())
            }
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text("Active ingredients")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ccSecondary)
            ForEach(result.activeIngredients, id: \.self) { ingredient in
                Text(ingredient)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }

    private var interactionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Label("Overlap with current medications", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ccDanger)
            ForEach(interactions) { match in
                interactionRow(match)
            }
            Text("Ingredient overlap is a starting point — it does not replace a pharmacist's interaction check.")
                .font(.caption)
                .foregroundStyle(Color.ccSecondary)
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccDanger.opacity(0.08))
        )
    }

    private var actions: some View {
        Button(action: onAdd) {
            Label("Add to medications", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.ccPrimary)
        .accessibilityHint("Open the add-medication form pre-filled with this drug.")
    }

    private var disclaimer: some View {
        Text("Not medical advice — consult your healthcare provider.")
            .font(.footnote)
            .foregroundStyle(Color.ccSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.ccSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.ccText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func interactionRow(_ match: InteractionChecker.Match) -> some View {
        HStack(alignment: .top, spacing: Theme.tightSpacing) {
            Image(systemName: "pills.fill")
                .font(.body)
                .foregroundStyle(Color.ccDanger)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.medicationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Text("Shares \(match.ingredient)")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private extension String {
    func titlecased() -> String {
        split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }
}
