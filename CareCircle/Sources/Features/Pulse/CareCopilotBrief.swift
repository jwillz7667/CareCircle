import Foundation

// MARK: - CareCopilotBrief

/// Pure composer that distils a Circle's current state into a brief
/// spoken/text answer for the AI Co-pilot. Synthesizes vitals trend,
/// anomaly load, dose adherence today, upcoming appointments, and the
/// latest activity entry into a single 4–6 sentence paragraph.
///
/// All composition is local — no network calls, no PHI leaving the
/// device. The "AI" here is a deterministic narrator over derived
/// signals the rest of the app already computes. iOS 26's Foundation
/// Models can swap in later as a smarter narrator without changing
/// the surface.
@MainActor
enum CareCopilotBrief {
    struct Output: Sendable {
        let speakable: String
        let highlights: [Highlight]
    }

    struct Highlight: Identifiable, Sendable {
        let id: UUID
        let icon: String
        let title: String
        let detail: String
        let severity: Severity

        init(icon: String, title: String, detail: String, severity: Severity) {
            id = UUID()
            self.icon = icon
            self.title = title
            self.detail = detail
            self.severity = severity
        }
    }

    enum Severity: Sendable {
        case info, watch, alert
    }

    static func brief(circle: Circle, now: Date = .now) -> Output {
        let recipientName = circle.careRecipient?.fullName.split(separator: " ").first.map(String.init)
            ?? "the Care Recipient"
        let summaries = VitalsAnalytics.summarize(vitals: circle.vitals)
        let highlights = composeHighlights(circle: circle, summaries: summaries, now: now)
        let speakable = composeSpeakable(
            recipientName: recipientName,
            summaries: summaries,
            highlights: highlights,
            now: now
        )
        return Output(speakable: speakable, highlights: highlights)
    }

    // MARK: - Composition

    private static func composeHighlights(
        circle: Circle,
        summaries: [VitalsAnalytics.KindSummary],
        now: Date
    )
        -> [Highlight]
    {
        var highlights: [Highlight] = []

        for anomaly in summaries.filter(\.isAnomalous).prefix(3) {
            let z = anomaly.zScore.map { String(format: "%+.1fσ", $0) } ?? ""
            highlights.append(Highlight(
                icon: anomaly.kind.systemImageName,
                title: "\(anomaly.kind.displayName) outside baseline",
                detail: "Latest \(anomaly.kind.shortName) \(z) from 14-day average.",
                severity: .alert
            ))
        }

        highlights.append(contentsOf: doseHighlights(circle: circle, now: now))

        let upcomingAppointments = circle.appointments
            .filter { $0.startsAt >= now && $0.startsAt < now.addingTimeInterval(7 * 86_400) }
            .sorted { $0.startsAt < $1.startsAt }
        if let appt = upcomingAppointments.first {
            highlights.append(Highlight(
                icon: "calendar",
                title: "Appointment \(VitalFormatting.relativeRecordedAt(appt.startsAt))",
                detail: appt.title,
                severity: .watch
            ))
        }

        let openSOS = circle.sosEvents.contains(where: { $0.status == .active })
        if openSOS {
            highlights.insert(Highlight(
                icon: "sos",
                title: "Active SOS event",
                detail: "Check the SOS tab immediately.",
                severity: .alert
            ), at: 0)
        }

        return highlights
    }

    /// Highlights derived from today's dose schedule: overdue, delivered,
    /// and the next upcoming dose.
    private static func doseHighlights(circle: Circle, now: Date) -> [Highlight] {
        let dayStart = Calendar.current.startOfDay(for: now)
        let todaysDoses: [DoseEvent] = circle.medications
            .flatMap(\.doseEvents)
            .filter { $0.scheduledAt >= dayStart }
        let overdue = todaysDoses.filter { $0.status == .scheduled && $0.scheduledAt <= now }
        let taken = todaysDoses.filter { $0.status == .taken }
        let dueLater = todaysDoses
            .filter { $0.status == .scheduled && $0.scheduledAt > now }
            .sorted { $0.scheduledAt < $1.scheduledAt }

        var highlights: [Highlight] = []
        if !overdue.isEmpty {
            let joined = overdue.compactMap { $0.medication?.name }.joined(separator: ", ")
            highlights.append(Highlight(
                icon: "pills.fill",
                title: "\(overdue.count) overdue \(overdue.count == 1 ? "dose" : "doses")",
                detail: joined.isEmpty ? "Tap Meds to review." : joined,
                severity: .alert
            ))
        }
        if !taken.isEmpty {
            highlights.append(Highlight(
                icon: "checkmark.seal.fill",
                title: "\(taken.count) \(taken.count == 1 ? "dose" : "doses") delivered today",
                detail: "Adherence on track.",
                severity: .info
            ))
        }
        if let next = dueLater.first {
            highlights.append(Highlight(
                icon: "clock.fill",
                title: "Next dose at \(timeOnlyFormatter.string(from: next.scheduledAt))",
                detail: next.medication?.name ?? "",
                severity: .info
            ))
        }
        return highlights
    }

    private static func composeSpeakable(
        recipientName: String,
        summaries: [VitalsAnalytics.KindSummary],
        highlights: [Highlight],
        now: Date
    )
        -> String
    {
        let presentSummaries = summaries.filter(\.hasData)
        guard !presentSummaries.isEmpty else {
            return "I don't have any vitals for \(recipientName) yet today. "
                + "Once an Apple Watch reading lands or someone records a manual entry, "
                + "I'll have something to brief you on."
        }

        var sentences: [String] = []
        let score = VitalsAnalytics.wellnessScore(from: summaries) ?? 100
        sentences.append(scoreSentence(recipientName: recipientName, score: score))
        sentences.append(contentsOf: vitalSentences(presentSummaries: presentSummaries))

        let anomalies = presentSummaries.filter(\.isAnomalous)
        if !anomalies.isEmpty {
            let names = anomalies.prefix(2).map(\.kind.displayName)
                .joined(separator: " and ")
            sentences.append(
                "One thing to check: \(names) is currently outside the rolling baseline."
            )
        }
        let medsAlerts = highlights.filter {
            $0.icon == "pills.fill" || $0.icon == "clock.fill"
        }
        if let firstMedAlert = medsAlerts.first {
            sentences.append(firstMedAlert.title + ".")
        }
        let stamp = now.formatted(date: .omitted, time: .shortened)
        sentences.append("That's the brief as of \(stamp). Not medical advice.")
        return sentences.joined(separator: " ")
    }

    /// One-line wellness verdict keyed off the composite score band.
    private static func scoreSentence(recipientName: String, score: Int) -> String {
        switch score {
        case 80...:
            "\(recipientName) looks steady — wellness composite \(score) out of 100."
        case 60 ..< 80:
            "\(recipientName)'s wellness composite is \(score), with a few signals worth watching."
        case 40 ..< 60:
            "Heads up: \(recipientName)'s wellness composite is \(score). Two or more readings are off baseline."
        default:
            "Alert: \(recipientName)'s wellness composite is \(score). Multiple readings are well outside the 14-day baseline."
        }
    }

    /// Narration for the headline vitals (heart rate, sleep, steps) when present.
    private static func vitalSentences(presentSummaries: [VitalsAnalytics.KindSummary]) -> [String] {
        var sentences: [String] = []
        if let hr = presentSummaries.first(where: { $0.kind == .heartRate }),
           let value = hr.latest, let baseline = hr.baseline
        {
            let dir = hr.trend == .rising ? "trending up" : hr.trend == .falling ? "trending down" : "tracking flat"
            sentences.append(
                "Heart rate is \(Int(value.value.rounded())) bpm, \(dir) against a baseline of \(Int(baseline.mean.rounded()))."
            )
        }
        if let sleep = presentSummaries.first(where: { $0.kind == .sleepHours }),
           let value = sleep.latest
        {
            sentences.append(
                "Last night's sleep was \(String(format: "%.1f", value.value)) hours."
            )
        }
        if let steps = presentSummaries.first(where: { $0.kind == .stepCount }),
           let value = steps.latest
        {
            let stepCount = Int(value.value.rounded())
            sentences.append("Step count so far today is \(stepCount.formatted()).")
        }
        return sentences
    }

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
