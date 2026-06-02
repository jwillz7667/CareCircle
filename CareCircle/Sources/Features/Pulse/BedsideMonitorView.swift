import Combine
import SwiftData
import SwiftUI
import UIKit

// MARK: - BedsideMonitorView

/// Ambient full-screen monitor — turns the phone into a hospital-style
/// bedside display for overnight watching. Big numbers, dark
/// background, a live ECG-style waveform, an emergency SOS button, and
/// idle-timer disabled while the screen is mounted. Optimised for being
/// glanced at across a dim room.
///
/// Updates push through the same `BackendRealtimeClient` that drives
/// the rest of the app, so when an Apple Watch sample lands in HK and
/// fans out through the backend, the bedside reading refreshes within
/// seconds.
struct BedsideMonitorView: View {
    let circle: Circle

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(BackendRealtimeClient.self) private var realtimeClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Latest reading per vital, derived from a single
    /// `VitalsAnalytics.summarize` pass. Computed once per body evaluation
    /// (not once per metric, and — because the clock lives in its own
    /// subview — not on every per-second tick).
    private struct Readings {
        var heartRate: Double?
        var oxygen: Double?
        var temperature: Double?
        var respRate: Double?
        var systolic: Double?
        var diastolic: Double?

        init(vitals: [Vital]) {
            let summaries = VitalsAnalytics.summarize(vitals: vitals)
            func latest(_ kind: VitalKind) -> Double? {
                summaries.first { $0.kind == kind }?.latest?.value
            }
            heartRate = latest(.heartRate)
            oxygen = latest(.oxygenSaturation)
            temperature = latest(.bodyTemperature)
            respRate = latest(.respiratoryRate)
            systolic = latest(.bloodPressureSystolic)
            diastolic = latest(.bloodPressureDiastolic)
        }

        var hrText: String {
            guard let heartRate else { return "—" }
            return "\(Int(heartRate.rounded()))"
        }

        var bpText: String {
            guard let systolic, let diastolic else { return "—" }
            return "\(Int(systolic.rounded()))/\(Int(diastolic.rounded()))"
        }
    }

    var body: some View {
        let readings = Readings(vitals: circle.vitals)
        return ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                topBar
                centerStack(readings: readings)
                Spacer()
                metricGrid(readings: readings)
                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(circle.careRecipient?.fullName ?? circle.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text(realtimeClient.isConnected ? "Live • Streaming" : "Offline cache")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(realtimeClient.isConnected ? Color.green : Color.gray)
            }
            Spacer()
            BedsideClock()
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .accessibilityLabel("Exit bedside monitor")
        }
    }

    private func centerStack(readings: Readings) -> some View {
        VStack(spacing: 8) {
            ECGWaveformView(bpm: readings.heartRate ?? 72, tint: Color.green, reduceMotion: reduceMotion)
                .frame(height: 140)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(readings.hrText)
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.green)
                    .shadow(color: Color.green.opacity(0.4), radius: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text("BPM")
                        .font(.caption.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(Color.green.opacity(0.7))
                    Text("Heart rate")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private func metricGrid(readings: Readings) -> some View {
        HStack(spacing: 14) {
            metric(
                value: readings.oxygen.map { "\(Int($0.rounded()))" } ?? "—",
                unit: "%",
                label: "SpO₂",
                tint: Color.cyan
            )
            metric(
                value: readings.respRate.map { "\(Int($0.rounded()))" } ?? "—",
                unit: "/min",
                label: "Resp",
                tint: Color.yellow
            )
            metric(
                value: readings.bpText,
                unit: "mmHg",
                label: "BP",
                tint: Color.orange
            )
            metric(
                value: readings.temperature.map { String(format: "%.1f", $0) } ?? "—",
                unit: "°F",
                label: "Temp",
                tint: Color.pink
            )
        }
    }

    private func metric(value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(tint.opacity(0.85))
            Text(value)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.4), radius: 6)
            Text(unit)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - BedsideClock

/// The live HH:mm:ss clock. Owns its own 1 Hz timer so the per-second
/// redraw is scoped to this small subview — the parent monitor (and its
/// vitals analytics) only re-evaluates when the readings actually change.
private struct BedsideClock: View {
    @State private var now: Date = .now
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(clockString)
            .font(.system(size: 36, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))
            .onReceive(tick) { now = $0 }
            .accessibilityLabel("Current time")
    }

    private var clockString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: now)
    }
}

// MARK: - ECGWaveformView

/// Stylised PQRST-shape waveform that scrolls right-to-left at a rate
/// driven by the current heart rate. Pure SwiftUI shape — no Core
/// Animation, no MetalKit. The signal isn't a real ECG; it's a
/// visualisation of the *cadence* of the current HR so the screen
/// feels alive at a glance.
private struct ECGWaveformView: View {
    let bpm: Double
    let tint: Color
    /// When Reduce Motion is on, the timeline is paused so the trace
    /// renders as a single static frame instead of scrolling.
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                drawWave(into: ctx, size: size, time: context.date.timeIntervalSinceReferenceDate)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    private func drawWave(into ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        let height = size.height
        let width = size.width
        let midY = height / 2
        let beatPeriod = max(0.4, 60.0 / bpm)
        let scrollSpeed = width / 6.0
        let offset = time.truncatingRemainder(dividingBy: beatPeriod) / beatPeriod
        _ = offset

        let path = Path { path in
            path.move(to: CGPoint(x: 0, y: midY))
            for x in stride(from: 0.0, to: Double(width), by: 1.0) {
                let timeAt = time - (Double(width) - x) / Double(scrollSpeed)
                let local = timeAt.truncatingRemainder(dividingBy: beatPeriod) / beatPeriod
                let y = midY - waveform(at: local) * (height * 0.42)
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.stroke(
            path,
            with: .color(tint),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )
        var glow = ctx
        glow.addFilter(.blur(radius: 4))
        glow.stroke(
            path,
            with: .color(tint.opacity(0.5)),
            style: StrokeStyle(lineWidth: 4.0, lineCap: .round)
        )
    }

    /// Idealised PQRST trace mapped onto the 0…1 phase of a single
    /// beat. P bump, QRS spike, T bump. Just visualisation.
    private func waveform(at phase: Double) -> CGFloat {
        let p = (1 - cos(2 * .pi * phase * 8)) * 0.05
        let q = phase > 0.30 && phase < 0.34 ? -0.30 : 0
        let r = phase > 0.34 && phase < 0.38 ? 1.0 : 0
        let s = phase > 0.38 && phase < 0.42 ? -0.45 : 0
        let t = (phase > 0.55 && phase < 0.75)
            ? sin(.pi * (phase - 0.55) / 0.20) * 0.22
            : 0
        return CGFloat(p + q + r + s + t)
    }
}
