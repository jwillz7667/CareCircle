import Foundation
import MetricKit
import OSLog

// MARK: - CrashTelemetry

/// Bridges MetricKit's daily diagnostic payloads (crashes, hangs, CPU and
/// disk-write exceptions) into the unified log so field failures are
/// captured in device logs and sysdiagnoses instead of being invisible.
///
/// This is a no-dependency, no-network first step: MetricKit aggregates
/// diagnostics on device and delivers them at most once every 24 hours
/// (typically on the next launch after an event), so there is no runtime
/// cost on the hot path and nothing leaves the device. The payloads carry
/// stack traces and version metadata only — no app content — so they're
/// safe to log at `.public`. A remote sink can subscribe to the same
/// callback later without changing call sites.
///
/// `nonisolated` because MetricKit invokes the subscriber callbacks on its
/// own background queue, not the main actor; the type holds no mutable
/// state and only logs, so it's safe off any thread.
nonisolated final class CrashTelemetry: NSObject, MXMetricManagerSubscriber {
    /// Registers as a MetricKit subscriber. Must be retained for the
    /// process lifetime (MetricKit holds the subscriber weakly), so the
    /// owner — `AppDelegate` — keeps a strong reference.
    func start() {
        MXMetricManager.shared.add(self)
    }

    func stop() {
        MXMetricManager.shared.remove(self)
    }

    // Performance metrics aren't routed anywhere yet; diagnostics are the
    // signal we care about. Implemented to satisfy the protocol.
    func didReceive(_: [MXMetricPayload]) {}

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            log(payload.crashDiagnostics, kind: "crash")
            log(payload.hangDiagnostics, kind: "hang")
            log(payload.cpuExceptionDiagnostics, kind: "cpu-exception")
            log(payload.diskWriteExceptionDiagnostics, kind: "disk-write-exception")
        }
    }

    private func log(_ diagnostics: [some MXDiagnostic]?, kind: String) {
        guard let diagnostics, !diagnostics.isEmpty else { return }
        for diagnostic in diagnostics {
            let json = String(decoding: diagnostic.jsonRepresentation(), as: UTF8.self)
            AppLogger.app.fault(
                "MetricKit \(kind, privacy: .public) diagnostic: \(json, privacy: .public)"
            )
        }
    }
}
