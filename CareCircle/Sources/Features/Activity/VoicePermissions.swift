import AVFoundation
import Foundation
import OSLog
import Speech

// MARK: - VoicePermissions

struct VoicePermissionsResult: Sendable, Equatable {
    let microphoneGranted: Bool
    let speechGranted: Bool

    var canTranscribe: Bool {
        microphoneGranted && speechGranted
    }

    var canRecord: Bool {
        microphoneGranted
    }
}

enum VoicePermissions {
    static func current() -> VoicePermissionsResult {
        let mic: Bool = if #available(iOS 17.0, *) {
            AVAudioApplication.shared.recordPermission == .granted
        } else {
            AVAudioSession.sharedInstance().recordPermission == .granted
        }
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        return VoicePermissionsResult(microphoneGranted: mic, speechGranted: speech)
    }

    static func request() async -> VoicePermissionsResult {
        let mic = await requestMicrophone()
        let speech = await requestSpeech()
        let result = VoicePermissionsResult(microphoneGranted: mic, speechGranted: speech)
        AppLogger.persistence.info(
            "Voice permissions resolved mic=\(mic, privacy: .public) speech=\(speech, privacy: .public)"
        )
        return result
    }

    private static func requestMicrophone() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
