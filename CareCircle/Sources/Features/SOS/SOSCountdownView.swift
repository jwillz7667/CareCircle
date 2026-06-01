import OSLog
import SwiftData
import SwiftUI

// MARK: - SOSCountdownView

/// Full-screen countdown surface shown the moment SOS is armed. Big cancel
/// button dominates the layout; the ring renders the seconds remaining so
/// the user can read it without parsing text. Haptics are driven by
/// `SOSCenter`; we don't fire them from the view so cancel + fire happen
/// in one place.
struct SOSCountdownView: View {
    let circle: Circle
    let user: SignedInUser
    @Bindable var center: SOSCenter

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.red.opacity(0.92).ignoresSafeArea()

            VStack(spacing: Theme.looseSpacing) {
                Text("SOS")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)

                ZStack {
                    SwiftUI.Circle()
                        .stroke(.white.opacity(0.25), lineWidth: 12)

                    SwiftUI.Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)

                    VStack(spacing: 4) {
                        Text("\(secondsRemaining)")
                            .font(.system(size: 96, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())

                        Text(secondsRemaining == 1 ? "second" : "seconds")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: 240, height: 240)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(secondsRemaining) seconds until SOS fires")

                Text("Release will alert your Circle and call your primary contact.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, Theme.looseSpacing)
            }
            .padding(.top, Theme.looseSpacing)

            VStack {
                Spacer()
                cancelButton
                    .padding(.horizontal, Theme.looseSpacing)
                    .padding(.bottom, Theme.looseSpacing)
            }
        }
        .onAppear { startCountdown() }
        .onChange(of: center.state) { _, newValue in
            switch newValue {
            case .fired, .canceled:
                dismiss()
            default:
                break
            }
        }
        .interactiveDismissDisabled()
    }

    private var cancelButton: some View {
        Button {
            center.cancel()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                Text("Cancel SOS")
                    .font(.title2.weight(.heavy))
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(.white)
            .foregroundStyle(.red)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .accessibilityLabel("Cancel SOS countdown")
    }

    private var secondsRemaining: Int {
        if case let .arming(value) = center.state { return value }
        return 0
    }

    private var progress: Double {
        guard case let .arming(value) = center.state else { return 1 }
        return 1 - (Double(value) / 30.0)
    }

    private func startCountdown() {
        guard case .idle = center.state else { return }
        Task {
            do {
                try await center.arm(
                    in: circle,
                    triggeredBy: user,
                    modelContext: modelContext
                )
            } catch {
                AppLogger.sos.error(
                    "Failed to arm SOS: \(error.localizedDescription, privacy: .public)"
                )
                dismiss()
            }
        }
    }
}
