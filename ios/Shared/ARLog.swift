import Foundation
import os

/// Unified logging for main app + broadcast extension.
/// Prints locally; extension logs also POST to Mac relay when configured via `configureRelay`.
enum ARLog {
    private static let subsystem = "com.androidremote"

    private struct RelayTarget {
        let host: String
        let port: Int
        var sessionId: String?
    }

    private static let relayLock = NSLock()
    private nonisolated(unsafe) static var relay: RelayTarget?

    /// Forward extension/app logs to Mac relay terminal (`POST /debug/log`).
    static func configureRelay(host: String, port: Int, sessionId: String? = nil) {
        relayLock.lock()
        relay = RelayTarget(host: host, port: port, sessionId: sessionId)
        relayLock.unlock()
        info("Log", "relay forwarding → http://\(host):\(port)/debug/log")
    }

    static func clearRelay() {
        relayLock.lock()
        relay = nil
        relayLock.unlock()
    }

    static func info(_ component: String, _ message: String) {
        emit(component, message, level: .info, levelName: "info")
    }

    static func warn(_ component: String, _ message: String) {
        emit(component, message, level: .default, levelName: "warn")
    }

    static func error(_ component: String, _ message: String) {
        emit(component, message, level: .error, levelName: "error")
    }

    private static func emit(_ component: String, _ message: String, level: OSLogType, levelName: String) {
        let line = "[AndroidRemote|\(component)] \(message)"
        print(line)
        Logger(subsystem: subsystem, category: component).log(level: level, "\(message, privacy: .public)")
        forwardToRelay(component: component, level: levelName, message: message)
    }

    private static func forwardToRelay(component: String, level: String, message: String) {
        relayLock.lock()
        let target = relay
        relayLock.unlock()
        guard let target else { return }
        guard let url = URL(string: "http://\(target.host):\(target.port)/debug/log") else { return }

        Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 3
            struct Body: Encodable {
                let component: String
                let level: String
                let message: String
                let sessionId: String?
            }
            let body = Body(
                component: component,
                level: level,
                message: message,
                sessionId: target.sessionId
            )
            request.httpBody = try? JSONEncoder().encode(body)
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    static func sessionPrefix(_ sessionId: String) -> String {
        sessionId.count >= 8 ? String(sessionId.prefix(8)) + "…" : sessionId
    }
}
