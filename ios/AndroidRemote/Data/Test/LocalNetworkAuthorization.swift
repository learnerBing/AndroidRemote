import Foundation
import Network

/// Triggers the iOS Local Network permission dialog (required for LAN TCP server).
final class LocalNetworkAuthorization: @unchecked Sendable {
    static let shared = LocalNetworkAuthorization()

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.androidremote.local-network-auth")

    private init() {}

    func requestAuthorization() {
        guard browser == nil else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_androidremote-test._tcp", domain: nil), using: params)
        browser.stateUpdateHandler = { _ in }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
