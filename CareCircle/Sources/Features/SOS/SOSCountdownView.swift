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
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.red.opacity(0.92).ignoresSafeArea()

            if let firedEventID {
                firedConfirmation(eventID: firedEventID)
            } else {
                armingContent
            }
        }
        .onAppear { startCountdown() }
        .onChange(of: center.state) { _, newValue in
            // Stay on-screen when fired so the user sees confirmation and the
            // one-tap call CTA. Only a cancel pops the cover automatically.
            if case .canceled = newValue { dismiss() }
        }
        .interactiveDismissDisabled()
    }

    private var armingContent: some View {
        ZStack {
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

                Text(
                    "When the countdown ends, your Circle is alerted and your location is shared. Tap Cancel if this was accidental."
                )
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
    }

    private func firedConfirmation(eventID: UUID) -> some View {
        let sharedLocation = firedEvent(eventID)?.hasLocation == true
        return VStack(spacing: Theme.spacing) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityHidden(true)

            Text("SOS sent")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(
                sharedLocation
                    ? "Your Circle has been alerted and your location was shared."
                    : "Your Circle has been alerted."
            )
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, Theme.looseSpacing)

            Spacer()

            VStack(spacing: Theme.spacing) {
                if let contact = primaryContact {
                    Button {
                        callPrimary(contact, eventID: eventID)
                    } label: {
                        Label("Call \(contact.name)", systemImage: "phone.fill")
                            .font(.title2.weight(.heavy))
                            .frame(maxWidth: .infinity, minHeight: 88)
                            .background(.white)
                            .foregroundStyle(.red)
                            .clipShape(
                                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            )
                    }
                    .accessibilityLabel("Call \(contact.name)")
                    .accessibilityHint("Places a phone call. CareCircle does not call automatically.")

                    Text("Calling is up to you — CareCircle does not place the call automatically.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("No primary contact set. Add one under Emergency contacts.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                }

                Button("Done") { dismiss() }
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.6), lineWidth: 1.5)
                    )
                    .accessibilityHint("Closes this screen. The SOS stays active until resolved.")
            }
            .padding(.horizontal, Theme.looseSpacing)
            .padding(.bottom, Theme.looseSpacing)
        }
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

    private var firedEventID: UUID? {
        if case let .fired(id) = center.state { return id }
        return nil
    }

    private var primaryContact: EmergencyContact? {
        circle.emergencyContacts.first(where: \.isPrimary)
    }

    private func firedEvent(_ eventID: UUID) -> SOSEvent? {
        circle.sosEvents.first { $0.id == eventID }
    }

    private func callPrimary(_ contact: EmergencyContact, eventID: UUID) {
        let sanitized = contact.phoneE164.filter { $0.isNumber || $0 == "+" }
        guard !sanitized.isEmpty, let url = URL(string: "tel://\(sanitized)") else { return }
        if let event = firedEvent(eventID) {
            event.primaryContactCalled = true
            try? modelContext.save()
        }
        openURL(url)
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
