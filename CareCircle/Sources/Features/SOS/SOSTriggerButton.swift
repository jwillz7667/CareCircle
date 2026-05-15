import SwiftUI

// MARK: - SOSTriggerButton

/// The big red SOS button. Visual press progresses while held; releasing
/// before the 3-second mark cancels the arm. This is the pocket-trigger
/// guard mentioned in the build plan — a normal tap won't fire SOS, only
/// an intentional sustained press will.
struct SOSTriggerButton: View {
    let isAvailable: Bool
    let onArm: () -> Void

    private let holdSeconds = 3.0
    @State private var holdProgress: Double = 0
    @State private var isPressing = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isAvailable ? Color.red : Color.red.opacity(0.4))

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.2))
                .scaleEffect(x: holdProgress, y: 1, anchor: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .animation(.linear(duration: 0.05), value: holdProgress)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                Image(systemName: "sos.circle.fill")
                    .font(.system(size: 24, weight: .black))
                Text(isAvailable ? "Hold 3s for SOS" : "SOS unavailable")
                    .font(.headline.weight(.heavy))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, Theme.tightSpacing)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAvailable ? "SOS" : "SOS unavailable")
        .accessibilityHint("Hold this button for 3 seconds to start the SOS countdown.")
        .accessibilityAddTraits(.isButton)
        .gesture(longPressGesture)
        .disabled(!isAvailable)
    }

    private var longPressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in handlePressDown() }
            .onEnded { _ in handlePressUp() }
    }

    private func handlePressDown() {
        guard isAvailable, !isPressing else { return }
        isPressing = true
        holdProgress = 0
        let started = Date.now
        holdTask = Task {
            while !Task.isCancelled {
                let elapsed = Date.now.timeIntervalSince(started)
                let next = min(elapsed / holdSeconds, 1.0)
                await MainActor.run { holdProgress = next }
                if next >= 1.0 {
                    await MainActor.run {
                        if isPressing {
                            isPressing = false
                            holdProgress = 0
                            onArm()
                        }
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func handlePressUp() {
        guard isPressing else { return }
        isPressing = false
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
    }
}
