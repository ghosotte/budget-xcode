import Foundation
import Network
import Observation

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "budget.networkmonitor")
    private var wasOffline = false
    private var onReconnect: (() async -> Void)?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let online = path.status == .satisfied
                let justReconnected = !self.isOnline && online
                self.isOnline = online
                if justReconnected {
                    await self.onReconnect?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func setReconnectHandler(_ handler: @escaping () async -> Void) {
        onReconnect = handler
    }
}
