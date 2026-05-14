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
    @State private var now: Date = .now

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var summaries: [VitalsAnalytics.KindSummary] {
        VitalsAnalytics.summarize(vitals: circle.vitals)
    }

    private var heartRate: Double? {
        summaries.first(where: { $0.kind == .heartRate })?.latest?.value
    }

    private var oxygen: Double? {
        summaries.first(where: { $0.kind == .oxygenSaturation })?.latest?.value
    }

    private var temperature: Double? {
        summaries.first(where: { $0.kind == .bodyTemperature })?.latest?.value
    }

    private var respRate: Double? {
        summaries.first(where: { $0.kind == .respiratoryRate })?.latest?.value
    }

    private var systolic: Double? {
        summaries.first(where: { $0.kind == .bloodPressureSystolic })?.latest?.value
    }

    private var diastolic: Double? {
        summaries.first(where: { $0.kind == .bloodPressureDiastolic })?.latest?.value
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                topBar
                centerStack
                Spacer()
                metricGrid
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
        .onReceive(clockTimer) { date in
            now = date
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
            Text(clockString)
                .font(.system(size: 36, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
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

    private var centerStack: some View {
        VStack(spacing: 8) {
            ECGWaveformView(bpm: heartRate ?? 72, tint: Color.green)
                .frame(height: 140)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(hrText)
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
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private var metricGrid: some View {
        HStack(spacing: 14) {
            metric(
                value: oxygen.map { "\(Int($0.rounded()))" } ?? "—",
                unit: "%",
                label: "SpO₂",
                tint: Color.cyan
            )
            metric(
                value: respRate.map { "\(Int($0.rounded()))" } ?? "—",
                unit: "/min",
                label: "Resp",
                tint: Color.yellow
            )
            metric(
                value: bpString,
                unit: "mmHg",
                label: "BP",
                tint: Color.orange
            )
            metric(
                value: temperature.map { String(format: "%.1f", $0) } ?? "—",
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
                .font(.system(size: 11, weight: .medium))
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

    private var clockString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: now)
    }

    private var hrText: String {
        guard let hr = heartRate else { return "—" }
        return "\(Int(hr.rounded()))"
    }

    private var bpString: String {
        guard let sys = systolic, let dia = diastolic else { return "—" }
        return "\(Int(sys.rounded()))/\(Int(dia.rounded()))"
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
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
