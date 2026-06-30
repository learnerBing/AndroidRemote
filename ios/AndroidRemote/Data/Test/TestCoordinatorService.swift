import Foundation

/// Shared LAN pairing coordinator — stays alive while test mode is active.
final class TestCoordinatorService: @unchecked Sendable {
    static let shared = TestCoordinatorService()

    let server = TestCoordinatorServer()
    private var running = false
    private let lock = NSLock()

    private init() {}

    @discardableResult
    func ensureStarted(advertisedIP: String?) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if running { return true }
        try server.start(advertisedIP: advertisedIP)
        running = true
        return true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        server.stop()
        running = false
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }
}
