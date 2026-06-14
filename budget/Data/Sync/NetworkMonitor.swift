import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline: Bool = true
    private(set) var lastReconnectAt: Date?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "budget.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let online = path.status == .satisfied
                let justReconnected = !self.isOnline && online
                self.isOnline = online
                if justReconnected {
                    self.lastReconnectAt = Date()
                }
            }
        }
        monitor.start(queue: queue)
    }
}
