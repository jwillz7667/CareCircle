import SwiftUI

// MARK: - PulseHeroCard

/// Hero card for the Pulse tab — a stylised "live presence" of the Care
/// Recipient. A central glyph pulses at the current heart rate, a halo
/// ring breathes at the respiratory rate, and the surrounding chrome
/// shows companion vitals (SpO₂, temperature) as satellite chips.
///
/// All animation is driven by `TimelineView(.animation)` — when the
/// view is offscreen SwiftUI stops calling the timeline, so the
/// animation has zero cost when the user isn't looking at it.
///
/// Designed to feel like a wearable's "now" face rather than a list
/// row — the screen real estate justifies the ambition.
struct PulseHeroCard: View {
    let heartRate: Double?
    let respiratoryRate: Double?
    let oxygenSaturation: Double?
    let bodyTemperature: Double?
    let sourceLabel: String
    let isLive: Bool

    private var bpm: Double {
        heartRate ?? 72
    }

    private var beatPeriod: Double {
        max(0.4, 60.0 / bpm)
    }

    private var breathPeriod: Double {
        60.0 / max(8, respiratoryRate ?? 14)
    }

    var body: some View {
        ZStack {
            backgroundGradient
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    breathRing(t: t)
                    pulseCore(t: t)
                    centerLabel
                }
            }
            satelliteChips
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius * 1.5))
        .overlay(alignment: .topLeading) { liveBadge }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.ccPrimary.opacity(0.92),
                Color.ccText.opacity(0.94),
                Color.black.opacity(0.85),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [Color.white.opacity(0.18), .clear],
                center: .top,
                startRadius: 4,
                endRadius: 240
            )
        )
    }

    private func breathRing(t: TimeInterval) -> some View {
        let phase = (sin(2 * .pi * t / breathPeriod) + 1) / 2
        return SwiftUI.Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.05),
                    ]),
                    center: .center
                ),
                lineWidth: 2
            )
            .frame(width: 220, height: 220)
            .scaleEffect(0.92 + 0.06 * phase)
            .opacity(0.55 + 0.35 * phase)
            .blur(radius: 0.4)
    }

    private func pulseCore(t: TimeInterval) -> some View {
        let beatPhase = abs(sin(2 * .pi * t / beatPeriod))
        let scale = 1.0 + 0.08 * beatPhase
        return ZStack {
            SwiftUI.Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.ccPrimary.opacity(0.55),
                            Color.ccPrimary.opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 110
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(scale)
                .opacity(0.65 + 0.30 * beatPhase)
                .blur(radius: 8)

            Image(systemName: "heart.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
                .scaleEffect(0.96 + 0.10 * beatPhase)
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 2) {
            Spacer().frame(height: 120)
            if let hr = heartRate {
                Text("\(Int(hr.rounded()))")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("BPM · \(sourceLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.8))
            } else {
                Text("--")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                Text("Awaiting heart rate")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
    }

    private var satelliteChips: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                if let spo2 = oxygenSaturation {
                    chip(systemName: "lungs.fill", value: "\(Int(spo2.rounded()))%", caption: "SpO₂")
                }
                if let temp = bodyTemperature {
                    chip(
                        systemName: "thermometer.medium",
                        value: String(format: "%.1f°", temp),
                        caption: "Temp"
                    )
                }
                if let rr = respiratoryRate {
                    chip(systemName: "wind", value: "\(Int(rr.rounded()))", caption: "Resp")
                }
            }
            .padding(.bottom, 14)
            .padding(.horizontal, 14)
        }
    }

    private func chip(systemName: String, value: String, caption: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .opacity(0.75)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            SwiftUI.Circle()
                .fill(isLive ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
                .shadow(color: isLive ? Color.green : .clear, radius: 4)
            Text(isLive ? "LIVE" : "OFFLINE")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
        .padding(14)
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let hr = heartRate {
            parts.append("Heart rate \(Int(hr.rounded())) beats per minute")
        }
        if let spo2 = oxygenSaturation {
            parts.append("Oxygen saturation \(Int(spo2.rounded())) percent")
        }
        if let temp = bodyTemperature {
            parts.append("Temperature \(String(format: "%.1f", temp)) degrees")
        }
        if parts.isEmpty {
            return "Pulse monitor, awaiting readings."
        }
        return "Pulse monitor. " + parts.joined(separator: ". ")
    }
}
