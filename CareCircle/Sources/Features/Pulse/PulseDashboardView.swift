import SwiftData
import SwiftUI

// MARK: - PulseDashboardView

/// The "Pulse" tab — a futuristic live monitor that visualises the
/// Care Recipient's current state across all tracked vitals. Composes
/// the hero pulse card, wellness score, anomaly callouts, and a
/// 2-column grid of `VitalTile`s. Hosts the entry points to the
/// Bedside ambient monitor and the AI Care Co-pilot.
struct PulseDashboardView: View {
    let authState: AuthState

    @Query(sort: \Circle.createdAt) private var circles: [Circle]
    @Environment(\.modelContext) private var modelContext
    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @Environment(HealthKitVitalsReader.self) private var healthKitReader
    @State private var isShowingBedside = false
    @State private var isShowingCopilot = false
    @State private var isSyncingHealth = false

    private var activeCircle: Circle? {
        guard case let .signedIn(user) = authState.status else {
            return circles.first
        }
        return circles.first(where: { $0.ownerAppleUserID == user.id }) ?? circles.first
    }

    private var signedInUser: SignedInUser? {
        if case let .signedIn(user) = authState.status { return user }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let circle = activeCircle {
                    dashboard(for: circle)
                } else {
                    emptyState
                }
            }
            .background(Color.ccBackground.ignoresSafeArea())
            .navigationTitle("Pulse")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar { toolbar }
        }
        .fullScreenCover(isPresented: $isShowingBedside) {
            if let circle = activeCircle {
                BedsideMonitorView(circle: circle)
            }
        }
        .sheet(isPresented: $isShowingCopilot) {
            if let circle = activeCircle, let user = signedInUser {
                CareCopilotView(
                    circle: circle,
                    authorDisplayName: user.displayName
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let circle = activeCircle {
                Button {
                    isShowingCopilot = true
                } label: {
                    Image(systemName: "sparkles")
                        .accessibilityLabel("Open Care Co-pilot")
                }
                .featureGate(.careCopilot, circle: circle, viewerAppleUserID: signedInUser?.id ?? "")
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "waveform.path.ecg.rectangle.fill",
            title: "No Circle yet",
            message: "Create a Circle to see live vitals stream in from Apple Watch and the Health app."
        )
    }

    private func dashboard(for circle: Circle) -> some View {
        let summaries = VitalsAnalytics.summarize(vitals: circle.vitals)
        let score = VitalsAnalytics.wellnessScore(from: summaries)
        let anomalies = summaries.filter(\.isAnomalous)

        return ScrollView {
            VStack(spacing: Theme.spacing) {
                PulseHeroCard(
                    heartRate: latestValue(summaries, kind: .heartRate),
                    respiratoryRate: latestValue(summaries, kind: .respiratoryRate),
                    oxygenSaturation: latestValue(summaries, kind: .oxygenSaturation),
                    bodyTemperature: latestValue(summaries, kind: .bodyTemperature),
                    sourceLabel: sourceLabel(summaries: summaries),
                    isLive: realtimeClient.isConnected
                )

                WellnessRing(
                    score: score,
                    trendLabel: trendLabel(from: summaries),
                    subtitle: wellnessSubtitle(summaries: summaries, anomalies: anomalies)
                )

                if !anomalies.isEmpty {
                    AnomalyCallout(summaries: anomalies)
                }

                actionsRow

                BloodPressurePairTile(summaries: summaries)

                tilesGrid(summaries: summaries)

                DisclaimerFooter()
                    .padding(.top, Theme.spacing)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.top, Theme.spacing)
            .padding(.bottom, Theme.looseSpacing)
        }
        .refreshable {
            await refresh(circle: circle)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: Theme.tightSpacing) {
            let circle = activeCircle
            let viewerID = signedInUser?.id ?? ""

            actionButton(
                title: "Bedside Mode",
                systemImage: "waveform.path.ecg.rectangle.fill",
                accent: Color.ccPrimary
            ) {
                isShowingBedside = true
            }
            .featureGateIfPresent(.bedsideMonitor, circle: circle, viewerAppleUserID: viewerID)

            actionButton(
                title: "Ask Co-pilot",
                systemImage: "sparkles",
                accent: Color.purple.opacity(0.85)
            ) {
                isShowingCopilot = true
            }
            .featureGateIfPresent(.careCopilot, circle: circle, viewerAppleUserID: viewerID)

            actionButton(
                title: isSyncingHealth ? "Syncing…" : "Sync Health",
                systemImage: isSyncingHealth ? "arrow.triangle.2.circlepath" : "heart.text.square.fill",
                accent: Color.pink
            ) {
                guard let circle = activeCircle else { return }
                Task { await syncHealth(circle: circle) }
            }
            .disabled(isSyncingHealth || !healthKitReader.isAvailable)
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        accent: Color,
        action: @escaping () -> Void
    )
        -> some View
    {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [accent.opacity(0.95), accent.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
            )
            .shadow(color: accent.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func tilesGrid(summaries: [VitalsAnalytics.KindSummary]) -> some View {
        let presentation = VitalKind.allCases.filter { kind in
            kind != .bloodPressureSystolic && kind != .bloodPressureDiastolic
        }
        let displayed = presentation.compactMap { kind in
            summaries.first(where: { $0.kind == kind && $0.hasData })
        }
        let columns = [
            GridItem(.flexible(), spacing: Theme.tightSpacing),
            GridItem(.flexible(), spacing: Theme.tightSpacing),
        ]
        return Group {
            if displayed.isEmpty {
                noDataCard
            } else {
                LazyVGrid(columns: columns, spacing: Theme.tightSpacing) {
                    ForEach(displayed) { summary in
                        VitalTile(summary: summary)
                    }
                }
            }
        }
    }

    private var noDataCard: some View {
        VStack(spacing: Theme.tightSpacing) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.ccPrimary)
            Text("Waiting for your first reading")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ccText)
            Text(
                "Wear your Apple Watch or open Health on the Care Recipient's device. Vitals will flow in here automatically and update across the Circle in realtime."
            )
            .font(.footnote)
            .foregroundStyle(Color.ccSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.cardCornerRadius).fill(Color.ccSurface))
    }

    // MARK: - Helpers

    private func latestValue(
        _ summaries: [VitalsAnalytics.KindSummary],
        kind: VitalKind
    )
        -> Double?
    {
        summaries.first(where: { $0.kind == kind })?.latest?.value
    }

    private func sourceLabel(summaries: [VitalsAnalytics.KindSummary]) -> String {
        let latest = summaries.compactMap(\.latest).sorted { $0.recordedAt > $1.recordedAt }
        guard let top = latest.first else { return "no signal" }
        let relative = VitalFormatting.relativeRecordedAt(top.recordedAt)
        let provenance = top.source == .healthkit ? "Apple Health" : "manual"
        return "\(relative) · \(provenance)"
    }

    private func trendLabel(from summaries: [VitalsAnalytics.KindSummary]) -> String? {
        let trending = summaries.first(where: { $0.kind == .heartRate && $0.trend != .unknown })
        guard let trending, let delta = trending.trendDeltaPercent else { return nil }
        let sign = delta > 0 ? "+" : ""
        return "HR \(sign)\(String(format: "%.0f", delta))% vs 14-day"
    }

    private func wellnessSubtitle(
        summaries: [VitalsAnalytics.KindSummary],
        anomalies: [VitalsAnalytics.KindSummary]
    )
        -> String
    {
        if !anomalies.isEmpty {
            let names = anomalies.prefix(2).map(\.kind.shortName).joined(separator: ", ")
            let suffix = anomalies.count > 2 ? "and more" : ""
            return "Watching \(names) \(suffix). Pull to refresh, or tap Sync Health."
        }
        let withData = summaries.filter(\.hasData).count
        if withData == 0 { return "Connect Apple Health to begin streaming." }
        return "All readings tracking baseline across \(withData) signals."
    }

    private func refresh(circle: Circle) async {
        async let backend: Void = realtimeClient.snapshotResync(
            circleIds: [circle.id],
            modelContext: modelContext
        )
        async let health: Void = readHealthKitSafely(circle: circle)
        _ = await (backend, health)
    }

    private func syncHealth(circle: Circle) async {
        isSyncingHealth = true
        defer { isSyncingHealth = false }
        await readHealthKitSafely(circle: circle)
    }

    private func readHealthKitSafely(circle: Circle) async {
        guard healthKitReader.isAvailable else { return }
        _ = try? await healthKitReader.requestAuthorizationIfNeeded()
        await healthKitReader.readNewSamples(for: circle, modelContext: modelContext)
    }
}

// MARK: - AnomalyCallout

private struct AnomalyCallout: View {
    let summaries: [VitalsAnalytics.KindSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.ccDanger)
                Text("\(summaries.count) reading\(summaries.count == 1 ? "" : "s") outside the 14-day baseline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
            }
            ForEach(summaries) { summary in
                row(for: summary)
            }
            Text("Anomaly = current value more than 2σ from rolling baseline. Heuristic, not diagnostic.")
                .font(.system(.caption2))
                .foregroundStyle(Color.ccSecondary)
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccDanger.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(Color.ccDanger.opacity(0.35), lineWidth: 1)
        )
    }

    private func row(for summary: VitalsAnalytics.KindSummary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: summary.kind.systemImageName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(summary.kind.tintColor)
                .frame(width: 18)
            Text(summary.kind.displayName)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.ccText)
            Spacer(minLength: 0)
            if let latest = summary.latest {
                Text(VitalFormatting.formattedValue(latest.value, kind: summary.kind))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.ccDanger)
            }
            if let z = summary.zScore {
                Text(String(format: "%+.1fσ", z))
                    .font(.system(.caption2, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(Color.ccDanger.opacity(0.85), in: Capsule())
            }
        }
    }
}

// MARK: - BloodPressurePairTile

private struct BloodPressurePairTile: View {
    let summaries: [VitalsAnalytics.KindSummary]

    private var systolic: VitalsAnalytics.KindSummary? {
        summaries.first(where: { $0.kind == .bloodPressureSystolic && $0.hasData })
    }

    private var diastolic: VitalsAnalytics.KindSummary? {
        summaries.first(where: { $0.kind == .bloodPressureDiastolic && $0.hasData })
    }

    var body: some View {
        if systolic != nil || diastolic != nil {
            HStack(spacing: Theme.spacing) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.ccDanger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blood pressure")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(systolicValue)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.ccText)
                        Text("/")
                            .font(.title3)
                            .foregroundStyle(Color.ccSecondary)
                        Text(diastolicValue)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.ccText)
                        Text("mmHg")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.ccSecondary)
                            .padding(.leading, 4)
                    }
                    Text(recordedLabel)
                        .font(.system(.caption2))
                        .foregroundStyle(Color.ccSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius).fill(Color.ccSurface)
            )
        }
    }

    private var systolicValue: String {
        guard let s = systolic?.latest else { return "—" }
        return VitalFormatting.formattedValue(s.value, kind: .bloodPressureSystolic)
    }

    private var diastolicValue: String {
        guard let d = diastolic?.latest else { return "—" }
        return VitalFormatting.formattedValue(d.value, kind: .bloodPressureDiastolic)
    }

    private var recordedLabel: String {
        let latest = [systolic?.latest, diastolic?.latest]
            .compactMap(\.self)
            .max(by: { $0.recordedAt < $1.recordedAt })
        guard let latest else { return "" }
        return VitalFormatting.relativeRecordedAt(latest.recordedAt) + " · " +
            (latest.source == .healthkit ? "Apple Health" : "manual")
    }
}
