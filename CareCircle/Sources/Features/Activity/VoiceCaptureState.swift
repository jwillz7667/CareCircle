import Foundation

// MARK: - VoiceCaptureState

enum VoiceCaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording
    case processing
    case ready(VoiceCaptureResult)
    case failed(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .requestingPermission, .recording, .processing: true
        case .idle, .ready, .failed: false
        }
    }
}

// MARK: - VoiceCaptureResult

struct VoiceCaptureResult: Equatable, Sendable {
    let audioData: Data
    let durationSeconds: Double
    let transcript: String
}
