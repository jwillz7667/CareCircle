import Foundation

// MARK: - TaskDebouncer

/// Coalesces rapid `schedule(_:)` calls into a single trailing-edge
/// execution. Useful when a batch of mutations (e.g., logging three
/// doses in quick succession) should produce just one downstream
/// recompute.
///
/// `schedule` cancels any previously scheduled task and resets the
/// delay. The wrapped operation always runs on the main actor — every
/// caller in this app already hops to the main actor for SwiftData
/// access, so we centralize the hop here.
@MainActor
final class TaskDebouncer {
    private let delay: Duration
    private var pending: Task<Void, Never>?

    init(delay: Duration) {
        self.delay = delay
    }

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        pending?.cancel()
        pending = Task { [delay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
