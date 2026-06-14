import Foundation
import MetricKit
import OSLog

final class MetricsCollector: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsCollector()

    private override init() {}

    func subscribe() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            AppLogger.data.info("MetricPayload \(payload.jsonRepresentation(), privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            AppLogger.data.error("DiagnosticPayload \(payload.jsonRepresentation(), privacy: .public)")
        }
    }
}
