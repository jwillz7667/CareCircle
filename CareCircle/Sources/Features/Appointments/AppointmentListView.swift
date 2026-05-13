import SwiftData
import SwiftUI

// MARK: - AppointmentListView

/// Circle-scoped calendar view: groups appointments into Today / Upcoming /
/// Past and exposes the add flow. Long-press / swipe affordances are deferred
/// to the detail view.
struct AppointmentListView: View {
    let circle: Circle

    @State private var isAdding = false

    private var sortedAppointments: [Appointment] {
        circle.appointments.sorted { $0.startsAt < $1.startsAt }
    }

    private var grouped: [AppointmentGroup] {
        let now = Date()
        let calendar = Calendar.current
        var today: [Appointment] = []
        var upcoming: [Appointment] = []
        var past: [Appointment] = []
        for appointment in sortedAppointments {
            if appointment.completedAt != nil || appointment.endsAt < now {
                past.append(appointment)
            } else if calendar.isDateInToday(appointment.startsAt) {
                today.append(appointment)
            } else {
                upcoming.append(appointment)
            }
        }
        var groups: [AppointmentGroup] = []
        if !today.isEmpty { groups.append(.init(kind: .today, items: today)) }
        if !upcoming.isEmpty { groups.append(.init(kind: .upcoming, items: upcoming)) }
        if !past.isEmpty { groups.append(.init(kind: .past, items: past.reversed())) }
        return groups
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            addButton
                .padding(.trailing, Theme.spacing)
                .padding(.bottom, Theme.spacing)
        }
        .background(Color.ccBackground)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.ccBackground, for: .navigationBar)
        .sheet(isPresented: $isAdding) {
            AddAppointmentView(circle: circle)
        }
    }

    @ViewBuilder
    private var content: some View {
        if circle.appointments.isEmpty {
            EmptyStateView(
                systemImage: "calendar.badge.plus",
                title: "No appointments yet",
                message: "Add visits so the Circle can prep, drive, and follow up together."
            )
        } else {
            List {
                ForEach(grouped) { group in
                    Section(group.kind.displayName) {
                        ForEach(group.items) { appointment in
                            NavigationLink {
                                AppointmentDetailView(appointment: appointment)
                            } label: {
                                AppointmentRowView(
                                    appointment: appointment,
                                    showsDate: group.kind != .today
                                )
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var addButton: some View {
        Button {
            isAdding = true
        } label: {
            Label("Add appointment", systemImage: "plus")
                .font(.body.weight(.semibold))
                .padding(.horizontal, Theme.spacing)
                .padding(.vertical, 12)
                .foregroundStyle(Color.white)
                .background(Capsule().fill(Color.ccPrimary))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 4)
        }
        .accessibilityHint("Add a new appointment for this Circle.")
    }
}

// MARK: - AppointmentGroup

private struct AppointmentGroup: Identifiable {
    enum Kind: String, Hashable {
        case today
        case upcoming
        case past

        var displayName: String {
            switch self {
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .past: "Past"
            }
        }
    }

    let kind: Kind
    let items: [Appointment]

    var id: Kind {
        kind
    }
}
