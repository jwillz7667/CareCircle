import SwiftData
import SwiftUI

// MARK: - SimplifiedHomeView

/// Single-screen home for the person being cared for. Designed for the
/// care recipient: oversized type, two big call/text buttons to the
/// primary family contact, a today's-medicine summary, and the next
/// appointment. When the mode was enabled manually (not by role), an
/// "Exit simplified mode" button is visible at the bottom so the
/// caregiver can switch back.
struct SimplifiedHomeView: View {
    let authState: AuthState
    let circle: Circle?
    let preference: SimplifiedModePreference

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var greetingName: String {
        if let recipient = circle?.careRecipient, !recipient.firstName.isEmpty {
            return recipient.firstName
        }
        if case let .signedIn(user) = authState.status {
            return user.givenName ?? user.displayName
        }
        return ""
    }

    private var primaryContact: EmergencyContact? {
        guard let contacts = circle?.emergencyContacts else { return nil }
        return contacts.first(where: \.isPrimary) ?? contacts.min(by: { $0.sortOrder < $1.sortOrder })
    }

    private var todaysDoses: [SimplifiedDoseSummary] {
        guard let medications = circle?.medications else { return [] }
        return SimplifiedDoseSummary.collect(from: medications, now: .now)
    }

    private var nextAppointment: Appointment? {
        guard let appointments = circle?.appointments else { return nil }
        let horizon = Date.now.addingTimeInterval(7 * 24 * 3_600)
        return appointments
            .filter { $0.startsAt >= .now && $0.startsAt <= horizon }
            .min(by: { $0.startsAt < $1.startsAt })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.looseSpacing) {
                    greeting
                    callTextButtons
                    medsSummaryCard
                    nextAppointmentCard
                    Spacer(minLength: Theme.looseSpacing)
                    if preference.isManualOverrideEnabled {
                        exitButton
                    }
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.top, Theme.looseSpacing)
                .padding(.bottom, Theme.looseSpacing)
            }
            .background(Color.ccBackground)
            .navigationBarHidden(true)
        }
        .transaction { txn in
            if reduceMotion { txn.animation = nil }
        }
    }

    private var greeting: some View {
        VStack(spacing: 6) {
            Text(greetingPhrase)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ccText)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.title3)
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.spacing)
        .accessibilityElement(children: .combine)
    }

    private var callTextButtons: some View {
        VStack(spacing: Theme.spacing) {
            if let contact = primaryContact {
                bigActionButton(
                    title: "Call \(contact.name)",
                    systemImage: "phone.fill",
                    color: Color.ccPrimary,
                    accessibilityHint: "Calls \(contact.name) at \(contact.phoneE164)"
                ) {
                    dial(contact)
                }
                bigActionButton(
                    title: "Text \(contact.name)",
                    systemImage: "message.fill",
                    color: Color.ccText,
                    accessibilityHint: "Opens Messages to \(contact.name)"
                ) {
                    message(contact)
                }
            } else {
                missingContactCard
            }
        }
    }

    private func bigActionButton(
        title: String,
        systemImage: String,
        color: Color,
        accessibilityHint: String,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            HStack(spacing: Theme.spacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .bold))
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.horizontal, Theme.spacing)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    private var missingContactCard: some View {
        VStack(spacing: Theme.tightSpacing) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(Color.ccSecondary)
            Text("No family contact set up")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Text("Ask your caregiver to add a primary emergency contact.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ccSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
    }

    private var medsSummaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack {
                Image(systemName: "pills.fill")
                    .font(.title2)
                    .foregroundStyle(Color.ccPrimary)
                Text("Today's medicine")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Spacer()
            }
            if todaysDoses.isEmpty {
                Text("No doses scheduled today.")
                    .font(.title3)
                    .foregroundStyle(Color.ccSecondary)
            } else {
                Text(medsHeadline)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.ccText)
                if let next = nextDose {
                    Text(
                        "Next: \(next.medicationName) at \(next.scheduledAt.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.title3)
                    .foregroundStyle(Color.ccSecondary)
                }
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
        .accessibilityElement(children: .combine)
    }

    private var nextAppointmentCard: some View {
        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(Color.ccPrimary)
                Text("Next appointment")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Spacer()
            }
            if let appointment = nextAppointment {
                Text(appointment.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                    .lineLimit(2)
                Text(appointment.startsAt.formatted(date: .complete, time: .shortened))
                    .font(.title3)
                    .foregroundStyle(Color.ccSecondary)
                if let provider = appointment.provider, !provider.isEmpty {
                    Text(provider)
                        .font(.title3)
                        .foregroundStyle(Color.ccSecondary)
                }
            } else {
                Text("Nothing scheduled this week.")
                    .font(.title3)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface)
        )
        .accessibilityElement(children: .combine)
    }

    private var exitButton: some View {
        Button {
            preference.isManualOverrideEnabled = false
        } label: {
            Text("Exit simplified mode")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.ccSecondary)
        .accessibilityHint("Returns to the standard CareCircle interface")
    }
}

// MARK: - SimplifiedHomeView helpers

private extension SimplifiedHomeView {
    var greetingPhrase: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let timeOfDay = switch hour {
        case 5 ..< 12: "Good morning"
        case 12 ..< 17: "Good afternoon"
        default: "Good evening"
        }
        return greetingName.isEmpty ? timeOfDay : "\(timeOfDay), \(greetingName)"
    }

    var medsHeadline: String {
        let total = todaysDoses.count
        let taken = todaysDoses.filter(\.isTaken).count
        let remaining = max(0, total - taken)
        if remaining == 0 {
            return "All \(total) doses taken today."
        }
        return "\(taken) of \(total) taken. \(remaining) to go."
    }

    var nextDose: SimplifiedDoseSummary? {
        todaysDoses
            .filter { !$0.isTaken && $0.scheduledAt >= .now.addingTimeInterval(-60) }
            .min(by: { $0.scheduledAt < $1.scheduledAt })
    }

    func dial(_ contact: EmergencyContact) {
        let sanitized = contact.phoneE164.filter { $0.isNumber || $0 == "+" }
        guard !sanitized.isEmpty, let url = URL(string: "tel://\(sanitized)") else { return }
        openURL(url)
    }

    func message(_ contact: EmergencyContact) {
        let sanitized = contact.phoneE164.filter { $0.isNumber || $0 == "+" }
        guard !sanitized.isEmpty, let url = URL(string: "sms:\(sanitized)") else { return }
        openURL(url)
    }
}

// MARK: - SimplifiedDoseSummary

/// Snapshot of one of today's medication doses, flattened so the view
/// doesn't have to know about MedicationSchedule details.
struct SimplifiedDoseSummary: Identifiable {
    let id: String
    let medicationName: String
    let scheduledAt: Date
    let isTaken: Bool

    static func collect(from medications: [Medication], now: Date) -> [SimplifiedDoseSummary] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        var summaries: [SimplifiedDoseSummary] = []
        for medication in medications where medication.status == .active {
            let recorded = medication.doseEvents.filter {
                $0.scheduledAt >= dayStart && $0.scheduledAt < dayEnd
            }
            let recordedTimes = Set(recorded.map(\.scheduledAt))
            for event in recorded {
                summaries.append(SimplifiedDoseSummary(
                    id: "rec-\(event.id.uuidString)",
                    medicationName: medication.name,
                    scheduledAt: event.scheduledAt,
                    isTaken: event.status == .taken || event.status == .late
                ))
            }
            let upcoming = medication.schedule
                .upcomingOccurrences(after: dayStart.addingTimeInterval(-1), limit: 12)
                .filter { $0 < dayEnd && !recordedTimes.contains($0) }
            for occurrence in upcoming {
                summaries.append(SimplifiedDoseSummary(
                    id: "sched-\(medication.id.uuidString)-\(occurrence.timeIntervalSince1970)",
                    medicationName: medication.name,
                    scheduledAt: occurrence,
                    isTaken: false
                ))
            }
        }
        return summaries.sorted { $0.scheduledAt < $1.scheduledAt }
    }
}
