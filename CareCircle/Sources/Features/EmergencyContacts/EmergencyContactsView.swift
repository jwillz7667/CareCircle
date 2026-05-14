import OSLog
import SwiftData
import SwiftUI

// MARK: - EmergencyContactsView

struct EmergencyContactsView: View {
    let circle: Circle

    @Environment(\.modelContext) private var modelContext
    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @State private var isPresentingAdd = false

    private var contacts: [EmergencyContact] {
        circle.emergencyContacts.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if contacts.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "phone.badge.plus",
                        title: "No emergency contacts",
                        message: "Add a primary contact so SOS knows who to call first."
                    )
                    .containerRelativeFrame(.vertical)
                }
                .refreshable {
                    await realtimeClient.snapshotResync(
                        circleIds: [circle.id],
                        modelContext: modelContext
                    )
                }
            } else {
                List {
                    ForEach(contacts, id: \.id) { contact in
                        EmergencyContactRow(contact: contact)
                    }
                    .onDelete(perform: deleteContacts)
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await realtimeClient.snapshotResync(
                        circleIds: [circle.id],
                        modelContext: modelContext
                    )
                }
            }
        }
        .navigationTitle("Emergency contacts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAdd = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddEmergencyContactView(circle: circle)
        }
        .background(Color.ccBackground)
    }

    private func deleteContacts(at offsets: IndexSet) {
        let ordered = contacts
        for index in offsets {
            let contact = ordered[index]
            modelContext.delete(contact)
        }
        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to delete emergency contact: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

// MARK: - EmergencyContactRow

private struct EmergencyContactRow: View {
    let contact: EmergencyContact

    var body: some View {
        HStack(spacing: Theme.spacing) {
            ZStack {
                Color.ccSurface
                    .clipShape(.circle)
                Image(systemName: contact.isMedical ? "stethoscope" : "person.fill")
                    .foregroundStyle(Color.ccPrimary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(contact.name)
                        .font(.headline)
                        .foregroundStyle(Color.ccText)
                    if contact.isPrimary {
                        Text("PRIMARY")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                Text(contact.phoneE164)
                    .font(.subheadline)
                    .foregroundStyle(Color.ccSecondary)
                if let relationship = contact.relationship, !relationship.isEmpty {
                    Text(relationship)
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
