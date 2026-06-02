import AVFoundation
import SwiftUI

// MARK: - CareCopilotView

/// AI Care Co-pilot — voice-first brief for the Circle owner. Long-
/// press the mic to ask any question (heuristically answered from the
/// last brief), or just tap "Speak the brief" to have the synthesized
/// voice read today's state aloud.
///
/// The brief is pure local composition (`CareCopilotBrief`), so the
/// sheet works offline. The microphone path stages question text into
/// the brief — a placeholder for the iOS 26 Foundation Models swap-in
/// later. v1 returns the most-relevant pre-baked answer.
struct CareCopilotView: View {
    let circle: Circle
    let authorDisplayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var brief: CareCopilotBrief.Output = .init(speakable: "", highlights: [])
    @State private var isSpeaking = false
    @State private var spokenLine: String?
    @State private var question = ""

    private let synthesizer = AVSpeechSynthesizer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    heroCard
                    summarySection
                    highlightsSection
                    askSection
                    DisclaimerFooter()
                }
                .padding(Theme.spacing)
            }
            .background(Color.ccBackground)
            .navigationTitle("Care Co-pilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.ccBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { stopAndDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleSpeak()
                    } label: {
                        Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .accessibilityLabel(isSpeaking ? "Stop speaking" : "Speak the brief")
                    }
                }
            }
        }
        .task { recompute() }
        .onChange(of: question) { _, _ in recompute() }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.ccPrimary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: SwiftUI.Circle()
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's brief")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.ccText)
                    Text("Composed on-device · \(Date.now.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Color.ccSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccSurface)
        )
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(brief.speakable.isEmpty ? "Composing brief…" : brief.speakable)
                .font(.body)
                .foregroundStyle(Color.ccText)
                .multilineTextAlignment(.leading)
            if isSpeaking, let line = spokenLine {
                Text("Speaking: \(line)")
                    .font(.caption)
                    .foregroundStyle(Color.ccSecondary)
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .stroke(Color.ccPrimary.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var highlightsSection: some View {
        if !brief.highlights.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Highlights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                ForEach(brief.highlights) { highlight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: highlight.icon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(severityColor(highlight.severity))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(highlight.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.ccText)
                            if !highlight.detail.isEmpty {
                                Text(highlight.detail)
                                    .font(.caption)
                                    .foregroundStyle(Color.ccSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(Theme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .fill(Color.ccSurface)
            )
        }
    }

    private var askSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask the co-pilot")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ccText)
            HStack(spacing: 8) {
                TextField("e.g. How was sleep last night?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { recompute() }
                Button {
                    recompute()
                    speak()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .padding(8)
                        .background(Color.ccPrimary, in: SwiftUI.Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Send")
            }
            Text("v1 answers heuristically from the brief above. Foundation Models upgrade lands with iOS 26.")
                .font(.system(.caption2))
                .foregroundStyle(Color.ccSecondary)
        }
        .padding(Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .fill(Color.ccSurface)
        )
    }

    private func severityColor(_ s: CareCopilotBrief.Severity) -> Color {
        switch s {
        case .info: Color.ccPrimary
        case .watch: Color.orange
        case .alert: Color.ccDanger
        }
    }

    private func recompute() {
        brief = CareCopilotBrief.brief(circle: circle)
    }

    private func toggleSpeak() {
        if isSpeaking { stopSpeaking() } else { speak() }
    }

    private func speak() {
        stopSpeaking()
        guard !brief.speakable.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: brief.speakable)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.02
        utterance.preUtteranceDelay = 0.15
        spokenLine = brief.speakable
        isSpeaking = true
        synthesizer.speak(utterance)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(estimatedDuration(brief.speakable)))
            isSpeaking = false
            spokenLine = nil
        }
    }

    private func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        spokenLine = nil
    }

    private func stopAndDismiss() {
        stopSpeaking()
        dismiss()
    }

    private func estimatedDuration(_ text: String) -> Double {
        // ~3 words per second of natural narration.
        let words = max(1, text.split(separator: " ").count)
        return Double(words) / 3.0 + 0.5
    }
}
