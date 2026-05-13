import AVFoundation
import Foundation
import OSLog
import Speech

// MARK: - VoiceCaptureService

@MainActor
@Observable
final class VoiceCaptureService: NSObject {
    private(set) var state: VoiceCaptureState = .idle
    private(set) var liveTranscript = ""
    private(set) var elapsedSeconds: Double = 0
    private(set) var permissions: VoicePermissionsResult = VoicePermissions.current()

    private let session = AVAudioSession.sharedInstance()
    private let audioEngine = AVAudioEngine()
    private var recorder: AVAudioRecorder?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var tempURL: URL?
    private var meteringTask: Task<Void, Never>?
    private var quietSampleCount = 0
    private var recordingStartedAt: Date?

    private let minimumDurationSeconds = 1.0
    private let silenceThresholdDB: Float = -50
    private let silenceSamplesToStop = 20
    private let maximumDurationSeconds: Double = 90

    func start() async {
        guard !state.isBusy else { return }
        state = .requestingPermission
        liveTranscript = ""
        elapsedSeconds = 0
        quietSampleCount = 0

        let current = VoicePermissions.current()
        let granted = current.canRecord ? current : await VoicePermissions.request()
        permissions = granted
        guard granted.canRecord else {
            state = .failed("Microphone access is required to record a voice note.")
            return
        }

        do {
            try beginRecording(canTranscribe: granted.canTranscribe)
            state = .recording
            recordingStartedAt = Date()
            startMetering()
        } catch {
            AppLogger.persistence.error(
                "Voice capture start failed: \(String(describing: error), privacy: .public)"
            )
            tearDown()
            state = .failed("Couldn't start recording. Check microphone access.")
        }
    }

    func stop() async {
        guard state.isRecording else { return }
        state = .processing
        meteringTask?.cancel()
        meteringTask = nil

        let started = recordingStartedAt ?? Date()
        let duration = max(0, Date().timeIntervalSince(started))
        recordingStartedAt = nil

        stopCaptureStack()

        let transcript = await drainRecognition()
        recognitionTask = nil
        recognitionRequest = nil

        deactivateSession()
        finalizeRecording(duration: duration, transcript: transcript)
    }

    private func stopCaptureStack() {
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recorder?.stop()
    }

    private func deactivateSession() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            AppLogger.persistence.error(
                "AVAudioSession deactivate failed: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func finalizeRecording(duration: Double, transcript: String) {
        guard let finalURL = tempURL else {
            state = .failed("Recording was lost before it could be saved.")
            return
        }

        do {
            let data = try Data(contentsOf: finalURL)
            try? FileManager.default.removeItem(at: finalURL)
            tempURL = nil

            guard duration >= minimumDurationSeconds else {
                state = .failed("That was too short. Hold the button and speak for at least a second.")
                return
            }

            state = .ready(VoiceCaptureResult(
                audioData: data,
                durationSeconds: duration,
                transcript: transcript
            ))
        } catch {
            AppLogger.persistence.error(
                "Failed reading audio data: \(String(describing: error), privacy: .public)"
            )
            state = .failed("Couldn't save the recording. Please try again.")
        }
    }

    func cancel() {
        tearDown()
        state = .idle
    }

    func reset() {
        state = .idle
        liveTranscript = ""
        elapsedSeconds = 0
    }

    // MARK: - Private

    private func beginRecording(canTranscribe: Bool) throws {
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: [])

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.isMeteringEnabled = true
        guard newRecorder.record() else {
            throw VoiceCaptureFailure.recorderRefused
        }
        recorder = newRecorder
        tempURL = url

        if canTranscribe {
            setupRecognition()
        }
    }

    private func setupRecognition() {
        let locale = Locale(identifier: "en-US")
        guard let speech = SFSpeechRecognizer(locale: locale), speech.isAvailable else {
            AppLogger.persistence.info("Speech recognizer unavailable; skipping live transcript")
            return
        }
        speech.delegate = self
        speech.defaultTaskHint = .dictation
        recognizer = speech

        let request = makeRecognitionRequest(for: speech)
        guard startAudioEngine(feeding: request) else { return }

        recognitionRequest = request
        recognitionTask = speech.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.liveTranscript = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                Task { @MainActor in
                    self.recognitionTask = nil
                }
            }
        }
    }

    private func makeRecognitionRequest(for recognizer: SFSpeechRecognizer) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        return request
    }

    private func startAudioEngine(feeding request: SFSpeechAudioBufferRecognitionRequest) -> Bool {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            return true
        } catch {
            AppLogger.persistence.error(
                "Audio engine start failed: \(String(describing: error), privacy: .public)"
            )
            inputNode.removeTap(onBus: 0)
            return false
        }
    }

    private func startMetering() {
        meteringTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let started = recordingStartedAt ?? Date()
                let elapsed = Date().timeIntervalSince(started)
                elapsedSeconds = elapsed

                if elapsed >= maximumDurationSeconds {
                    await stop()
                    return
                }

                if elapsed < minimumDurationSeconds {
                    quietSampleCount = 0
                    continue
                }

                if power < silenceThresholdDB {
                    quietSampleCount += 1
                    if quietSampleCount >= silenceSamplesToStop {
                        await stop()
                        return
                    }
                } else {
                    quietSampleCount = 0
                }
            }
        }
    }

    private func drainRecognition() async -> String {
        guard let task = recognitionTask else { return liveTranscript }
        let deadline = Date().addingTimeInterval(1.5)
        while task.state != .completed, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        task.cancel()
        return liveTranscript
    }

    private func tearDown() {
        recorder?.stop()
        recorder = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        tempURL = nil
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceCaptureService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard !available else { return }
        Task { @MainActor in
            AppLogger.persistence.info("Speech recognizer became unavailable mid-session")
        }
    }
}

// MARK: - VoiceCaptureFailure

private enum VoiceCaptureFailure: Error {
    case recorderRefused
}
