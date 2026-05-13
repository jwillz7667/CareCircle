import SwiftData
import SwiftUI

// MARK: - MedicationListView

/// Circle-scoped medications list shown inside the Meds tab when a Circle
/// exists. Drives the add flow and pushes to `MedicationDetailView`.
struct MedicationListView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    @State private var isAddingMedication = false

    private var grouped: [(status: MedicationStatus, items: [Medication])] {
        let allMeds = circle.medications
        let byStatus = Dictionary(grouping: allMeds, by: { $0.status })
        return byStatus
            .map { ($0.key, $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.0.sortOrder < $1.0.sortOrder }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            addButton
                .padding(.trailing, Theme.spacing)
                .padding(.bottom, Theme.spacing)
        }
        .background(Color.ccBackground)
        .sheet(isPresented: $isAddingMedication) {
            AddMedicationView(circle: circle)
        }
    }

    @ViewBuilder
    private var content: some View {
        if circle.medications.isEmpty {
            VStack(spacing: 0) {
                EmptyStateView(
                    systemImage: "pills.fill",
                    title: "No medications yet",
                    message: "Add a medication to track doses, refills, and history."
                )

                DisclaimerFooter()
            }
        } else {
            List {
                ForEach(grouped, id: \.status) { group in
                    Section(group.status.displayName) {
                        ForEach(group.items) { medication in
                            NavigationLink {
                                MedicationDetailView(medication: medication, author: author)
                            } label: {
                                MedicationRowView(medication: medication)
                            }
                        }
                    }
                }

                Section {
                    MedicationDisclaimerFooter()
                        .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var addButton: some View {
        Button {
            isAddingMedication = true
        } label: {
            Label("Add medication", systemImage: "plus")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
                .foregroundStyle(Color.white)
                .background(
                    Capsule().fill(Color.ccPrimary)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
        }
        .accessibilityHint("Add a new medication to this Circle.")
    }
}
