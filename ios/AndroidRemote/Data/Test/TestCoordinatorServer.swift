import Foundation
import Network

/// LAN pairing coordinator (main app). Web receiver polls this until iPhone links a code.
final class TestCoordinatorServer: @unchecked Sendable {
    private struct LinkRecord {
        let sessionId: String
        let signalingHost: String
        let signalingPort: Int
    }

    private let port: UInt16
    private let queue = DispatchQueue(label: "com.androidremote.test-coordinator")
    private var listener: NWListener?
    private var linksByCode: [String: LinkRecord] = [:]
    private let lock = NSLock()

    init(port: UInt16 = TestReceiverConfig.coordinatorPort) {
        self.port = port
    }

    func registerLink(code: String, sessionId: String, signalingHost: String, signalingPort: Int) {
        lock.lock()
        linksByCode[code] = LinkRecord(
            sessionId: sessionId,
            signalingHost: signalingHost,
            signalingPort: signalingPort
        )
        lock.unlock()
    }

    func clearLink(code: String) {
        lock.lock()
        linksByCode.removeValue(forKey: code)
        lock.unlock()
    }

    func start(advertisedIP: String? = nil) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        listener.service = NWListener.Service(
            name: "AndroidRemote",
            type: "_androidremote-test._tcp",
            domain: nil,
            txtRecord: advertisedIP.flatMap { "ip=\($0)".data(using: .utf8) }
        )

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        linksByCode.removeAll()
        lock.unlock()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let response = self.route(request)
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func route(_ raw: String) -> String {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return HttpResponseBuilder.response(status: 400, body: "Bad request", contentType: "text/plain")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return HttpResponseBuilder.response(status: 400, body: "Bad request", contentType: "text/plain")
        }

        let method = String(parts[0])
        let pathAndQuery = String(parts[1])
        let path = pathAndQuery.split(separator: "?").first.map(String.init) ?? pathAndQuery
        let query = HttpResponseBuilder.parseQuery(pathAndQuery)

        if method == "OPTIONS" {
            return HttpResponseBuilder.response(status: 204, body: "", contentType: "text/plain", cors: true)
        }

        switch (method, path) {
        case ("GET", "/health"):
            return HttpResponseBuilder.json(ARCPHealthResponse(ok: true), cors: true)
        case ("GET", "/test/link"):
            return handleLinkGet(query: query)
        default:
            return HttpResponseBuilder.response(status: 404, body: "Not found", contentType: "text/plain", cors: true)
        }
    }

    private func handleLinkGet(query: [String: String]) -> String {
        guard let code = query["code"], let record = locked({ linksByCode[code] }) else {
            return HttpResponseBuilder.response(status: 204, body: "", contentType: "application/json", cors: true)
        }
        let payload = TestLinkResponse(
            sessionId: record.sessionId,
            signalingHost: record.signalingHost,
            signalingPort: record.signalingPort,
            state: "ready"
        )
        return HttpResponseBuilder.json(payload, cors: true)
    }

    private func locked<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}
