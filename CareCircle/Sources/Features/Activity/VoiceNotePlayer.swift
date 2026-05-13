import AVFoundation
import Foundation
import OSLog

// MARK: - VoiceNotePlayer

@MainActor
@Observable
final class VoiceNotePlayer: NSObject {
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var durationSeconds: Double = 0

    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    func toggle(data: Data, fallbackDuration: Double) {
        if isPlaying {
            pause()
            return
        }
        play(data: data, fallbackDuration: fallbackDuration)
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
    }

    private func play(data: Data, fallbackDuration: Double) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])

            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            durationSeconds = newPlayer.duration > 0 ? newPlayer.duration : fallbackDuration
            guard newPlayer.play() else {
                AppLogger.persistence.error("AVAudioPlayer refused to play voice note")
                return
            }
            player = newPlayer
            isPlaying = true
            startProgressTimer()
        } catch {
            AppLogger.persistence.error(
                "Voice playback failed: \(String(describing: error), privacy: .public)"
            )
            isPlaying = false
        }
    }

    private func pause() {
        progressTask?.cancel()
        progressTask = nil
        player?.pause()
        isPlaying = false
    }

    private func startProgressTimer() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let player else { return }
                if !player.isPlaying {
                    isPlaying = false
                    progressTask?.cancel()
                    progressTask = nil
                    return
                }
                let total = player.duration > 0 ? player.duration : durationSeconds
                progress = total > 0 ? player.currentTime / total : 0
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceNotePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
