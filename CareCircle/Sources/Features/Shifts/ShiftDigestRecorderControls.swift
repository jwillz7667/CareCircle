import SwiftUI

// MARK: - ShiftDigestRecorderControls

/// Compact recorder UI used inside the shift-digest composer. Wraps
/// the shared `VoiceCaptureService` state machine in the same way
/// `VoiceComposerView` does, but rendered inside a card alongside the
/// shift-window pickers so the caregiver sees the full handoff context
/// at a glance.
struct ShiftDigestRecorderControls: View {
    @Bindable var service: VoiceCaptureService
    let isSubmitting: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacing) {
            statusHeader
            transcriptArea
            actions
        }
    }

    private var statusHeader: some View {
        VStack(spacing: Theme.tightSpacing) {
            Text(headlineForState)
                .font(.headline)
                .foregroundStyle(Color.ccText)
                .multilineTextAlignment(.center)

            if case .recording = service.state {
                Text(formattedElapsed)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(Color.ccPrimary)
            }

            if case let .failed(message) = service.state {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.ccDanger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.spacing)
            }
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if case let .ready(result) = service.state {
            VStack(alignment: .leading, spacing: Theme.tightSpacing) {
                Text("Transcript")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ccSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(result.transcript.isEmpty
                    ? "(Transcript unavailable — your audio is still attached.)"
                    : result.transcript)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Theme.spacing)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.ccBackground)
            )
        } else if service.state.isRecording, !service.liveTranscript.isEmpty {
            ScrollView {
                Text(service.liveTranscript)
                    .font(.body)
                    .foregroundStyle(Color.ccText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.spacing)
            }
            .frame(maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color.ccBackground)
            )
        } else if case .processing = service.state {
            ProgressView("Finishing up…")
                .tint(Color.ccPrimary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch service.state {
        case .ready:
            HStack(spacing: Theme.spacing) {
                Button(role: .destructive) {
                    service.reset()
                } label: {
                    Label("Retake", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.ccDanger)
                .disabled(isSubmitting)

                Button(action: onSubmit) {
                    Label("Save digest", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ccPrimary)
                .disabled(isSubmitting)
            }
        case .failed:
            Button {
                Task { await service.start() }
            } label: {
                Label("Try again", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ccPrimary)
        default:
            MicButtonRow(state: service.state) {
                if service.state.isRecording {
                    Task { await service.stop() }
                } else {
                    Task { await service.start() }
                }
            }
        }
    }

    private var headlineForState: String {
        switch service.state {
        case .idle: "Hold the mic and narrate the handoff"
        case .requestingPermission: "Requesting permission…"
        case .recording: "Listening…"
        case .processing: "Wrapping up…"
        case .ready: "Ready to save"
        case .failed: "Something went wrong"
        }
    }

    private var formattedElapsed: String {
        let total = Int(service.elapsedSeconds.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - MicButtonRow

private struct MicButtonRow: View {
    let state: VoiceCaptureState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                SwiftUI.Circle()
                    .fill(buttonColor)
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
                Image(systemName: state.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isRecording ? "Stop recording" : "Start recording")
        .disabled(state == .requestingPermission || state == .processing)
    }

    private var buttonColor: Color {
        switch state {
        case .recording: Color.ccDanger
        case .processing, .requestingPermission: Color.ccSecondary
        default: Color.ccPrimary
        }
    }
}
