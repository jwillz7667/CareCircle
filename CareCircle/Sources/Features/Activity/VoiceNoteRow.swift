import SwiftUI

// MARK: - VoiceNoteRow

struct VoiceNoteRow: View {
    let audioData: Data
    let durationSeconds: Double

    @State private var player = VoiceNotePlayer()

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Button {
                player.toggle(data: audioData, fallbackDuration: durationSeconds)
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.ccPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pause voice note" : "Play voice note")

            VStack(alignment: .leading, spacing: 4) {
                Text(playbackLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ccText)
                Capsule()
                    .fill(Color.ccPrimary.opacity(0.18))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.ccPrimary)
                                .frame(width: max(0, geo.size.width * player.progress))
                        }
                    }
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, Theme.tightSpacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.ccSurface.opacity(0.7))
        )
        .onDisappear { player.stop() }
    }

    private var playbackLabel: String {
        if player.isPlaying {
            return "Playing voice note"
        }
        return "Voice note · \(formattedDuration)"
    }

    private var formattedDuration: String {
        let total = Int(durationSeconds.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
