import Foundation
import OSLog

// MARK: - AppLogger

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.jwillz.carecircle"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let cloudKit = Logger(subsystem: subsystem, category: "cloudkit")
    static let sos = Logger(subsystem: subsystem, category: "sos")
    static let backend = Logger(subsystem: subsystem, category: "backend")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let healthKit = Logger(subsystem: subsystem, category: "healthkit")
    static let subscriptions = Logger(subsystem: subsystem, category: "subscriptions")
}
