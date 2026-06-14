import Foundation
import OSLog
import SwiftData

enum AppLogger {
    private static let subsystem = "com.guilhemhosotte.budget"

    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let attest = Logger(subsystem: subsystem, category: "attest")
}

@MainActor
@Observable
final class SyncErrorStore {
    static let shared = SyncErrorStore()

    private(set) var lastError: String?
    private(set) var lastErrorAt: Date?

    private init() {}

    func record(_ message: String) {
        lastError = message
        lastErrorAt = Date()
    }

    func clear() {
        lastError = nil
        lastErrorAt = nil
    }
}

enum SyncErrorReporter {
    static func report(_ error: Error, context: String, level: OSLogType = .error, surfacing: Bool = false) {
        let message = "[\(context)] \(error.localizedDescription)"
        AppLogger.sync.log(level: level, "\(message, privacy: .public)")
        if surfacing {
            Task { @MainActor in
                SyncErrorStore.shared.record(error.localizedDescription)
            }
        }
    }

    static func report(_ message: String, context: String, level: OSLogType = .error) {
        AppLogger.sync.log(level: level, "[\(context, privacy: .public)] \(message, privacy: .public)")
    }
}

extension ModelContext {
    /// Save and report errors via SyncErrorReporter instead of swallowing silently.
    func safeSave(_ contextLabel: String) {
        do {
            try save()
        } catch {
            SyncErrorReporter.report(error, context: "save:\(contextLabel)")
        }
    }
}
