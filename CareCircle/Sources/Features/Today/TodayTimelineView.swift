import SwiftData
import SwiftUI

// MARK: - TodayTimelineView

/// Merged appointment + medication-dose timeline for the active Circle.
/// Entries are sorted chronologically and surface as a single list. The
/// dose entries reuse the same model the medication detail screen uses so
/// "mark taken / skipped" behaves identically here.
struct TodayTimelineView: View {
    let circle: Circle
    let author: ActivityAuthorContext

    private var todaysAppointments: [Appointment] {
        let calendar = Calendar.current
        return circle.appointments
            .filter { calendar.isDateInToday($0.startsAt) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var todaysDoses: [TodayDoseEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        var entries: [TodayDoseEntry] = []
        for medication in circle.medications where medication.status == .active {
            let recorded = medication.doseEvents.filter {
                $0.scheduledAt >= dayStart && $0.scheduledAt < dayEnd
            }
            let recordedTimes = Set(recorded.map(\.scheduledAt))
            for event in recorded {
                entries.append(TodayDoseEntry(
                    medication: medication,
                    occurrence: .recorded(event)
                ))
            }
            let upcoming = medication.schedule
                .upcomingOccurrences(after: dayStart.addingTimeInterval(-1), limit: 12)
                .filter { $0 < dayEnd && !recordedTimes.contains($0) }
            for occurrence in upcoming {
                entries.append(TodayDoseEntry(
                    medication: medication,
                    occurrence: .scheduled(occurrence)
                ))
            }
        }
        return entries
    }

    private var timelineEntries: [TodayTimelineEntry] {
        var entries: [TodayTimelineEntry] = []
        entries.append(contentsOf: todaysAppointments.map { TodayTimelineEntry.appointment($0) })
        entries.append(contentsOf: todaysDoses.map { TodayTimelineEntry.dose($0) })
        return entries.sorted { $0.sortKey < $1.sortKey }
    }

    var body: some View {
        if timelineEntries.isEmpty {
            EmptyStateView(
                systemImage: "sun.max.fill",
                title: "Nothing on the schedule",
                message: "Appointments and medication doses for today will appear here."
            )
            .background(Color.ccBackground)
        } else {
            List {
                Section("\(circle.name) — \(Date().formatted(date: .complete, time: .omitted))") {
                    ForEach(timelineEntries) { entry in
                        TodayTimelineRow(entry: entry, author: author)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ccBackground)
        }
    }
}

// MARK: - Timeline entry model

enum TodayTimelineEntry: Identifiable {
    case appointment(Appointment)
    case dose(TodayDoseEntry)

    var id: String {
        switch self {
        case let .appointment(appointment): "appt-\(appointment.id.uuidString)"
        case let .dose(entry): "dose-\(entry.id)"
        }
    }

    var sortKey: Date {
        switch self {
        case let .appointment(appointment): appointment.startsAt
        case let .dose(entry): entry.occurrence.date
        }
    }
}

struct TodayDoseEntry: Identifiable {
    let medication: Medication
    let occurrence: MedicationDoseRow.Occurrence

    var id: String {
        switch occurrence {
        case let .scheduled(date): "sched-\(medication.id.uuidString)-\(date.timeIntervalSince1970)"
        case let .recorded(event): "rec-\(event.id.uuidString)"
        }
    }
}

// MARK: - Timeline row

private struct TodayTimelineRow: View {
    let entry: TodayTimelineEntry
    let author: ActivityAuthorContext

    var body: some View {
        switch entry {
        case let .appointment(appointment):
            NavigationLink {
                AppointmentDetailView(appointment: appointment)
            } label: {
                AppointmentRowView(appointment: appointment, showsDate: false)
            }
        case let .dose(dose):
            MedicationDoseRow(
                medication: dose.medication,
                occurrence: dose.occurrence,
                author: author,
                onMarked: { _ in }
            )
        }
    }
}
