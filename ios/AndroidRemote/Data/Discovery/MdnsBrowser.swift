import Foundation
import Network

/// Browses for `_androidremote._tcp` services on the local network.
final class MdnsBrowser: DeviceDiscoveryRepository {
    private let browser: NWBrowser
    private var continuation: AsyncStream<[CastDevice]>.Continuation?
    private var devices: [String: CastDevice] = [:]

    var discoveredDevices: AsyncStream<[CastDevice]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield([])
        }
    }

    init() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_androidremote._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: .tcp)
        browser.stateUpdateHandler = { state in
            if case .failed = state {
                self.continuation?.yield([])
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleResults(results)
        }
    }

    func startBrowsing() async {
        browser.start(queue: .main)
    }

    func stopBrowsing() {
        browser.cancel()
        continuation?.finish()
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                resolveEndpoint(result.endpoint, name: name)
            }
        }
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, name: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
                let device = CastDevice(
                    id: name,
                    name: name,
                    host: "\(host)",
                    port: Int(port.rawValue)
                )
                self.devices[name] = device
                self.continuation?.yield(Array(self.devices.values))
            }
            connection.cancel()
        }
        connection.start(queue: .main)
    }
}
