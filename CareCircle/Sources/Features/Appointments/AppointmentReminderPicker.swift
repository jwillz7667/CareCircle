import SwiftUI

// MARK: - AppointmentReminderPicker

/// Reminder offset chips for an appointment draft. Each preset toggles a
/// minutes-before value in/out of the selection. Stored offsets that don't
/// match a preset (custom offsets, for backwards compatibility) are surfaced
/// in the footer so the user knows they're still active.
struct AppointmentReminderPicker: View {
    @Binding var selectedOffsets: [Int]

    private var presetOffsets: Set<Int> {
        Set(AppointmentReminderPreset.allCases.map(\.rawValue))
    }

    private var customOffsets: [Int] {
        selectedOffsets.filter { !presetOffsets.contains($0) }.sorted()
    }

    var body: some View {
        Section {
            ForEach(AppointmentReminderPreset.allCases) { preset in
                let isOn = selectedOffsets.contains(preset.rawValue)
                Toggle(preset.displayName, isOn: Binding(
                    get: { isOn },
                    set: { newValue in toggle(preset: preset, isOn: newValue) }
                ))
            }
        } header: {
            Text("Reminders")
        } footer: {
            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if selectedOffsets.isEmpty {
            Text("No reminders. Pick at least one to get notified.")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        } else if !customOffsets.isEmpty {
            Text("Also keeping custom offsets: \(customSummary).")
                .font(.footnote)
                .foregroundStyle(Color.ccSecondary)
        }
    }

    private var customSummary: String {
        customOffsets.map(formatMinutes).joined(separator: ", ")
    }

    private func toggle(preset: AppointmentReminderPreset, isOn: Bool) {
        if isOn {
            if !selectedOffsets.contains(preset.rawValue) {
                selectedOffsets.append(preset.rawValue)
                selectedOffsets.sort()
            }
        } else {
            selectedOffsets.removeAll { $0 == preset.rawValue }
        }
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }
}
