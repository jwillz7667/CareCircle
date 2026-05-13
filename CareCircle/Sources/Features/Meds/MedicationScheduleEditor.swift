import SwiftUI

// MARK: - MedicationScheduleEditor

/// Edits a `MedicationSchedule` in-place. Frequency picker drives which controls
/// are visible: `.asNeeded` hides time/day editors; `.weekly` reveals the weekday
/// chip row in addition to the time-of-day list.
struct MedicationScheduleEditor: View {
    @Binding var schedule: MedicationSchedule

    private static let weekdaySymbols: [(weekday: Int, label: String)] = {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (1 ... 7).map { ($0, symbols[$0 - 1]) }
    }()

    var body: some View {
        Section {
            Picker("Frequency", selection: $schedule.frequency) {
                ForEach(MedicationSchedule.Frequency.allCases, id: \.self) { frequency in
                    Text(frequency.displayName).tag(frequency)
                }
            }
            .accessibilityLabel("Medication frequency")

            if schedule.frequency == .weekly {
                weekdayPicker
            }

            if schedule.frequency != .asNeeded {
                timeList
            }
        } header: {
            Text("Schedule")
        } footer: {
            scheduleFooter
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            Text("Days of week")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.ccSecondary)

            HStack(spacing: Theme.tightSpacing) {
                ForEach(Self.weekdaySymbols, id: \.weekday) { entry in
                    weekdayChip(weekday: entry.weekday, label: entry.label)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func weekdayChip(weekday: Int, label: String) -> some View {
        let isOn = schedule.daysOfWeek.contains(weekday)
        return Button {
            toggleWeekday(weekday)
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(isOn ? Color.white : Color.ccText)
                .background(
                    SwiftUI.Circle().fill(isOn ? Color.ccPrimary : Color.ccSurface)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekdayAccessibilityLabel(weekday: weekday))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func weekdayAccessibilityLabel(weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let idx = max(0, min(weekday - 1, symbols.count - 1))
        return symbols[idx]
    }

    private func toggleWeekday(_ weekday: Int) {
        if schedule.daysOfWeek.contains(weekday) {
            schedule.daysOfWeek.remove(weekday)
        } else {
            schedule.daysOfWeek.insert(weekday)
        }
    }

    private var timeList: some View {
        VStack(spacing: 0) {
            if schedule.timesOfDay.isEmpty {
                Text("Add the times of day this medication is taken.")
                    .font(.footnote)
                    .foregroundStyle(Color.ccSecondary)
                    .padding(.vertical, Theme.tightSpacing)
            } else {
                ForEach($schedule.timesOfDay) { $time in
                    TimeOfDayRow(time: $time) {
                        remove(time: time)
                    }
                }
            }

            Button {
                addTime()
            } label: {
                Label("Add a time", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.ccPrimary)
            }
            .padding(.vertical, Theme.tightSpacing / 2)
        }
    }

    private func addTime() {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let suggested = MedicationSchedule.TimeOfDay(
            hour: now.hour ?? 8,
            minute: now.minute ?? 0
        )
        schedule.timesOfDay.append(suggested)
    }

    private func remove(time: MedicationSchedule.TimeOfDay) {
        schedule.timesOfDay.removeAll { $0.id == time.id }
    }

    @ViewBuilder
    private var scheduleFooter: some View {
        switch schedule.frequency {
        case .asNeeded:
            Text("No reminders will be scheduled. Doses can be logged whenever they're taken.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        case .daily:
            Text("Daily reminders will fire at each time you add.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        case .weekly:
            Text("Reminders fire only on the days you pick. Leave days unselected to skip the week.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        }
    }
}

// MARK: - TimeOfDayRow

private struct TimeOfDayRow: View {
    @Binding var time: MedicationSchedule.TimeOfDay
    let onDelete: () -> Void

    @State private var pickerDate: Date

    init(time: Binding<MedicationSchedule.TimeOfDay>, onDelete: @escaping () -> Void) {
        _time = time
        self.onDelete = onDelete
        var components = DateComponents()
        components.hour = time.wrappedValue.hour
        components.minute = time.wrappedValue.minute
        _pickerDate = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }

    var body: some View {
        HStack {
            DatePicker(
                "Time",
                selection: $pickerDate,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .onChange(of: pickerDate) { _, newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                time.hour = comps.hour ?? time.hour
                time.minute = comps.minute ?? time.minute
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.ccDanger)
                    .accessibilityLabel("Remove this time")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
