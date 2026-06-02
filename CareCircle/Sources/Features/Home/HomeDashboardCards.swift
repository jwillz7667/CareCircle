import SwiftData
import SwiftUI

// MARK: - HeaderStrip

/// Recipient name + status dot + tiny SOS pill. Lives at the very top
/// of the Today dashboard. The status line reflects the most urgent live
/// signal: an active SOS, then the top warning-severity Pulse insight,
/// otherwise "All quiet".
struct HomeHeaderStrip: View {
    let circle: Circle
    let onTriggerSOS: () -> Void

    private var recipientName: String {
        let name = circle.careRecipient?.fullName ?? ""
        return name.isEmpty ? circle.name : name
    }

    private var hasActiveSOS: Bool {
        circle.sosEvents.contains { $0.status == .active }
    }

    private var topWarning: Insight? {
        circle.insights
            .first { $0.dismissedAt == nil && $0.appliedAt == nil && $0.severity == .warning }
    }

    private var statusLine: String {
        if hasActiveSOS { return "SOS active" }
        if let topWarning { return topWarning.title }
        return "All quiet"
    }

    private var statusColor: Color {
        if hasActiveSOS { return .ccStatusCritical }
        if topWarning != nil { return .ccStatusAttention }
        return .ccStatusPositive
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipientName)
                    .font(.CC.titleMedium)
                    .foregroundStyle(Color.ccTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    statusColor
                        .frame(width: 8, height: 8)
                        .clipShape(.circle)
                    Text(statusLine)
                        .font(.CC.caption)
                        .foregroundStyle(Color.ccTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status: \(statusLine)")
            }

            Spacer()

            Button(action: onTriggerSOS) {
                Image(systemName: "sos")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.ccStatusCritical)
                    .frame(width: 40, height: 40)
                    .background(Color.ccStatusCritical.opacity(0.12), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arm SOS")
            .accessibilityHint("Opens the SOS arming screen. Hold for 3 seconds to start the countdown.")
        }
    }
}

// MARK: - PulseInsightCard

/// On-device Pulse insight surface. Shows the single most important
/// un-dismissed insight for entitled Circles, an upsell for free Circles,
/// and a "building up" placeholder when intelligence has nothing to say
/// yet. The whole card pushes the full `InsightsView`, so Pulse is always
/// reachable from Today.
struct HomePulseInsightCard: View {
    let circle: Circle
    let author: ActivityAuthorContext

    private var isEntitled: Bool {
        circle.entitles(.insights)
    }

    private var topInsight: Insight? {
        circle.insights
            .filter { $0.dismissedAt == nil && $0.appliedAt == nil }
            .min {
                if $0.severity.sortRank != $1.severity.sortRank {
                    return $0.severity.sortRank < $1.severity.sortRank
                }
                return $0.computedAt > $1.computedAt
            }
    }

    /// Headline shown in the card body. Free Circles see an upsell instead
    /// of insight content so the paywall is not bypassed.
    private var headline: String {
        guard isEntitled else {
            return "Unlock Pulse to surface patterns across meds, vitals, and visits."
        }
        return topInsight?.title ?? "Patterns will appear here as care data builds up."
    }

    private var detail: String? {
        guard isEntitled, let topInsight else { return nil }
        return topInsight.body
    }

    private var iconName: String {
        if isEntitled, topInsight?.severity == .warning {
            return "exclamationmark.triangle.fill"
        }
        return "sparkles"
    }

    private var iconColor: Color {
        if isEntitled, topInsight?.severity == .warning {
            return .ccDanger
        }
        return .ccAccent
    }

    var body: some View {
        NavigationLink {
            InsightsView(circle: circle, author: author)
        } label: {
            card
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pulse insight. \(headline)")
        .accessibilityHint("Opens the full list of insights for this Circle.")
    }

    private var card: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, alignment: .top)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pulse")
                    .font(.CC.label)
                    .foregroundStyle(Color.ccAccent)
                    .textCase(.uppercase)
                Text(headline)
                    .font(.CC.body)
                    .foregroundStyle(Color.ccTextPrimary)
                    .lineSpacing(Typography.lineSpacingDefault)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .font(.CC.caption)
                        .foregroundStyle(Color.ccTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text("On-device intelligence. Names and vitals never leave this device.")
                    .font(.CC.captionSmall)
                    .foregroundStyle(Color.ccTextSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.ccTextSecondary)
        }
        .padding(Spacing.m)
        .background(Color.ccAccentSoft, in: .rect(cornerRadius: Radius.card))
        .contentShape(.rect(cornerRadius: Radius.card))
    }
}

// MARK: - TodaysPlanCard

/// "What's coming up" — next three upcoming doses across all active
/// medications, plus the next non-completed appointment. Tapping "See
/// all" routes to the Meds tab.
struct HomeTodaysPlanCard: View {
    let circle: Circle
    let onSeeAll: () -> Void

    fileprivate struct UpcomingDose: Identifiable {
        let id = UUID()
        let medication: Medication
        let when: Date
    }

    private var upcomingDoses: [UpcomingDose] {
        let now = Date.now
        let merged = circle.medications
            .filter { $0.status == .active }
            .flatMap { med -> [UpcomingDose] in
                med.schedule.upcomingOccurrences(after: now, limit: 3).map {
                    UpcomingDose(medication: med, when: $0)
                }
            }
            .sorted(by: { $0.when < $1.when })
        return Array(merged.prefix(3))
    }

    private var nextAppointment: Appointment? {
        circle.appointments
            .filter { $0.startsAt > Date.now && !$0.isCompleted }
            .min(by: { $0.startsAt < $1.startsAt })
    }

    private var isEmpty: Bool {
        upcomingDoses.isEmpty && nextAppointment == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            header

            if isEmpty {
                Text("Nothing scheduled in the next few hours.")
                    .font(.CC.caption)
                    .foregroundStyle(Color.ccTextSecondary)
                    .padding(.vertical, Spacing.s)
            } else {
                ForEach(Array(upcomingDoses.enumerated()), id: \.element.id) { index, dose in
                    DoseRow(dose: dose)
                    if index != upcomingDoses.count - 1 || nextAppointment != nil {
                        Divider().background(Color.ccBorderHairline)
                    }
                }
                if let appointment = nextAppointment {
                    AppointmentRow(appointment: appointment)
                }
            }
        }
        .padding(Spacing.m)
        .background(Color.ccSurfacePrimary, in: .rect(cornerRadius: Radius.card))
    }

    private var header: some View {
        HStack {
            Text("Today's plan")
                .font(.CC.titleSmall)
                .foregroundStyle(Color.ccTextPrimary)
            Spacer()
            Button("See all", action: onSeeAll)
                .font(.CC.label)
                .tint(Color.ccAccent)
        }
    }
}

private struct DoseRow: View {
    let dose: HomeTodaysPlanCard.UpcomingDose

    private var timeString: String {
        dose.when.formatted(date: .omitted, time: .shortened)
    }

    private var dosageLine: String {
        let dosage = dose.medication.dosage.trimmingCharacters(in: .whitespaces)
        let scheduleHint = dose.medication.schedule.describesAnyTime
            ? ""
            : dose.medication.schedule.summary()
        return [dosage, scheduleHint].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: dose.medication.form.systemImageName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ccAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(dose.medication.name)
                    .font(.CC.bodyEmphasized)
                    .foregroundStyle(Color.ccTextPrimary)
                    .lineLimit(1)
                if !dosageLine.isEmpty {
                    Text(dosageLine)
                        .font(.CC.captionSmall)
                        .foregroundStyle(Color.ccTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(timeString)
                .font(.CC.numericDisplay)
                .foregroundStyle(Color.ccTextPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(dose.medication.name) \(dose.medication.dosage) at \(timeString)")
    }
}

private struct AppointmentRow: View {
    let appointment: Appointment

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "calendar")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.ccAccent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.title)
                    .font(.CC.bodyEmphasized)
                    .foregroundStyle(Color.ccTextPrimary)
                    .lineLimit(1)
                if let provider = appointment.provider?.trimmingCharacters(in: .whitespaces),
                   !provider.isEmpty
                {
                    Text(provider)
                        .font(.CC.captionSmall)
                        .foregroundStyle(Color.ccTextSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(appointment.startsAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.CC.captionSmall)
                    .foregroundStyle(Color.ccTextSecondary)
                Text(appointment.startsAt.formatted(date: .omitted, time: .shortened))
                    .font(.CC.bodyEmphasized.monospacedDigit())
                    .foregroundStyle(Color.ccTextPrimary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Appointment: \(appointment.title) on \(appointment.startsAt.formatted(date: .complete, time: .shortened))"
        )
    }
}

// MARK: - WhatChangedCard

/// "What changed since I last looked" — five most recent activities
/// from the Brain. Tapping "Open Brain" jumps to the Brain tab for the
/// full feed.
struct HomeWhatChangedCard: View {
    let circle: Circle
    let onSeeAll: () -> Void

    private var recent: [Activity] {
        Array(
            circle.activities
                .sorted(by: { $0.createdAt > $1.createdAt })
                .prefix(5)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("What changed")
                    .font(.CC.titleSmall)
                    .foregroundStyle(Color.ccTextPrimary)
                Spacer()
                Button("Open Brain", action: onSeeAll)
                    .font(.CC.label)
                    .tint(Color.ccAccent)
            }

            if recent.isEmpty {
                Text("No recent updates from your Circle.")
                    .font(.CC.caption)
                    .foregroundStyle(Color.ccTextSecondary)
                    .padding(.vertical, Spacing.s)
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, activity in
                    ChangeRow(activity: activity)
                    if index != recent.count - 1 {
                        Divider().background(Color.ccBorderHairline)
                    }
                }
            }
        }
        .padding(Spacing.m)
        .background(Color.ccSurfacePrimary, in: .rect(cornerRadius: Radius.card))
    }
}

private struct ChangeRow: View {
    let activity: Activity

    private var summary: String {
        let trimmed = activity.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? activity.type.displayName : trimmed
    }

    private var relativeTime: String {
        activity.createdAt.formatted(.relative(presentation: .named))
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: activity.type.systemImageName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ccAccent)
                .frame(width: 28, alignment: .top)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                    .font(.CC.body)
                    .foregroundStyle(Color.ccTextPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(activity.authorDisplayName)
                        .font(.CC.captionSmall)
                        .foregroundStyle(Color.ccTextSecondary)
                    Text("·")
                        .font(.CC.captionSmall)
                        .foregroundStyle(Color.ccTextSecondary)
                    Text(relativeTime)
                        .font(.CC.captionSmall)
                        .foregroundStyle(Color.ccTextSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.authorDisplayName), \(summary), \(relativeTime)")
    }
}

// MARK: - QuickCaptureFAB

/// The only verb on the Today dashboard. Opens a menu with the three
/// most-used composers: text/photo note, voice note, and end-of-shift
/// digest.
struct HomeQuickCaptureFAB: View {
    let onNote: () -> Void
    let onVoice: () -> Void
    let onDigest: () -> Void

    var body: some View {
        Menu {
            Button(action: onNote) {
                Label("Note or photo", systemImage: "square.and.pencil")
            }
            Button(action: onVoice) {
                Label("Voice note", systemImage: "mic.fill")
            }
            Button(action: onDigest) {
                Label("End-of-shift digest", systemImage: "waveform.path.ecg")
            }
        } label: {
            Label("Capture", systemImage: "plus")
                .font(.CC.bodyEmphasized)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 12)
                .foregroundStyle(.white)
                .background(Color.ccAccent, in: .capsule)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("Capture")
        .accessibilityHint("Open the quick capture menu: note, voice, or end-of-shift digest.")
    }
}
