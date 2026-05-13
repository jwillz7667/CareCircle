import OSLog
import SwiftUI

// MARK: - MedicationFDASection

/// openFDA cross-check section used inside `AddMedicationView`. Owns its own
/// lookup state so the parent form stays small. Writes the matched active
/// ingredients back into the draft via `savedIngredients`.
struct MedicationFDASection: View {
    let queryName: String
    @Binding var savedIngredients: [String]

    @State private var checkState: FDACheckState = .idle

    var body: some View {
        Section {
            checkButton

            switch checkState {
            case .idle, .loading:
                EmptyView()
            case .notFound:
                Text("No matching label found in openFDA.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
            case let .matched(result):
                resultView(result)
            case let .failed(message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.ccDanger)
            }
        } header: {
            Text("Drug information")
        } footer: {
            Text(
                "Looks up the medication name in the public openFDA label database. Used to confirm active ingredients — not as medical advice."
            )
            .font(.footnote)
            .foregroundStyle(Color.ccSecondary)
        }
    }

    private var checkButton: some View {
        Button {
            Task { await runCheck() }
        } label: {
            HStack {
                Label("Cross-check with openFDA", systemImage: "magnifyingglass")
                    .foregroundStyle(Color.ccPrimary)
                Spacer()
                if case .loading = checkState {
                    ProgressView().tint(Color.ccPrimary)
                }
            }
        }
        .disabled(queryName.isEmpty || checkState.isLoading)
    }

    private func resultView(_ result: OpenFDALabelResult) -> some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            if !result.brandNames.isEmpty {
                detailRow(title: "Brand", value: result.brandNames.joined(separator: ", "))
            }
            if !result.genericNames.isEmpty {
                detailRow(title: "Generic", value: result.genericNames.joined(separator: ", "))
            }
            if !result.activeIngredients.isEmpty {
                detailRow(
                    title: "Active ingredients",
                    value: result.activeIngredients.joined(separator: ", ")
                )
            }
            if !result.activeIngredients.isEmpty,
               result.activeIngredients != savedIngredients
            {
                Button {
                    savedIngredients = result.activeIngredients
                } label: {
                    Label("Save these ingredients", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.ccPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
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
    }

    private func runCheck() async {
        guard !queryName.isEmpty else { return }
        checkState = .loading
        do {
            if let result = try await OpenFDAClient().lookup(name: queryName) {
                checkState = .matched(result)
            } else {
                checkState = .notFound
            }
        } catch let error as OpenFDAClient.LookupError {
            checkState = .failed(error.localizedDescription)
        } catch {
            AppLogger.app.error(
                "openFDA lookup failed: \(String(describing: error), privacy: .public)"
            )
            checkState = .failed("Couldn't reach openFDA. Check your connection.")
        }
    }
}

// MARK: - FDACheckState

private enum FDACheckState {
    case idle
    case loading
    case notFound
    case matched(OpenFDALabelResult)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
