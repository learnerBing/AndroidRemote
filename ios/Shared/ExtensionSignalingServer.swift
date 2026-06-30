import Foundation
import Network

/// ARCP HTTP signaling relay that runs inside the Broadcast Extension on the iPhone.
/// The Cast web receiver connects to this server over LAN while the extension streams WebRTC.
final class ExtensionSignalingServer: @unchecked Sendable {
    private struct SessionState {
        var state = "waiting"
        var offer: String?
        var answer: String?
        var iceFromSender: [IceCandidate] = []
        var iceFromReceiver: [IceCandidate] = []
    }

    private let port: UInt16
    private let queue = DispatchQueue(label: "com.androidremote.extension-signaling")
    private var listener: NWListener?
    private var sessions: [String: SessionState] = [:]
    private let lock = NSLock()

    init(port: UInt16 = UInt16(CastConfig.signalingPort)) {
        self.port = port
    }

    func registerSession(_ sessionId: String) {
        lock.lock()
        sessions[sessionId] = SessionState()
        lock.unlock()
    }

    func updateConnectionState(_ sessionId: String, state: String) {
        lock.lock()
        sessions[sessionId]?.state = state
        lock.unlock()
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
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
        sessions.removeAll()
        lock.unlock()
    }

    // MARK: - HTTP

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
            return HttpResponseBuilder.response(status: 400, body: "Bad request", contentType: "text/plain", cors: true)
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return HttpResponseBuilder.response(status: 400, body: "Bad request", contentType: "text/plain", cors: true)
        }

        let method = String(parts[0])
        let pathAndQuery = String(parts[1])
        let path = pathAndQuery.split(separator: "?").first.map(String.init) ?? pathAndQuery
        let query = HttpResponseBuilder.parseQuery(pathAndQuery)

        if method == "OPTIONS" {
            return HttpResponseBuilder.response(status: 204, body: "", contentType: "text/plain", cors: true)
        }

        let body: String
        if let emptyIndex = raw.range(of: "\r\n\r\n") {
            body = String(raw[emptyIndex.upperBound...])
        } else if let emptyIndex = raw.range(of: "\n\n") {
            body = String(raw[emptyIndex.upperBound...])
        } else {
            body = ""
        }

        switch (method, path) {
        case ("GET", "/health"):
            return HttpResponseBuilder.json(ARCPHealthResponse(ok: true), cors: true)
        case ("GET", "/sdp/offer"):
            return handleOfferGet(query: query)
        case ("GET", "/sdp"):
            return handleAnswerGet(query: query)
        case ("POST", "/sdp"):
            return handleSdpPost(body: body)
        case ("GET", "/ice"):
            return handleIceGet(query: query)
        case ("POST", "/ice"):
            return handleIcePost(body: body, query: query)
        case ("GET", "/status"):
            return handleStatus(query: query)
        default:
            return HttpResponseBuilder.response(status: 404, body: "Not found", contentType: "text/plain", cors: true)
        }
    }

    private func handleOfferGet(query: [String: String]) -> String {
        guard let sessionId = query["sessionId"],
              let offer = locked({ sessions[sessionId]?.offer }) else {
            return HttpResponseBuilder.response(status: 204, body: "", contentType: "application/json", cors: true)
        }
        let message = ARCPSdpMessage(sessionId: sessionId, type: "offer", sdp: offer)
        return HttpResponseBuilder.json(message, cors: true)
    }

    private func handleAnswerGet(query: [String: String]) -> String {
        guard let sessionId = query["sessionId"],
              let answer = locked({ sessions[sessionId]?.answer }) else {
            return HttpResponseBuilder.response(status: 204, body: "", contentType: "application/json", cors: true)
        }
        let message = ARCPSdpMessage(sessionId: sessionId, type: "answer", sdp: answer)
        return HttpResponseBuilder.json(message, cors: true)
    }

    private func handleSdpPost(body: String) -> String {
        guard let message = try? JSONDecoder().decode(ARCPSdpMessage.self, from: Data(body.utf8)) else {
            return HttpResponseBuilder.response(status: 400, body: "Invalid JSON", contentType: "text/plain", cors: true)
        }
        lock.lock()
        var session = sessions[message.sessionId] ?? SessionState()
        if message.type == "offer" {
            session.offer = message.sdp
            session.state = "connecting"
        } else if message.type == "answer" {
            session.answer = message.sdp
        }
        sessions[message.sessionId] = session
        lock.unlock()
        return HttpResponseBuilder.json(["ok": true], cors: true)
    }

    private func handleIceGet(query: [String: String]) -> String {
        let sessionId = query["sessionId"] ?? ""
        let side = query["side"] ?? "receiver"
        lock.lock()
        var session = sessions[sessionId] ?? SessionState()
        let drained: [ARCPIceCandidateDto]
        if side == "sender" {
            drained = session.iceFromSender.map {
                ARCPIceCandidateDto(candidate: $0.candidate, sdpMid: $0.sdpMid, sdpMLineIndex: $0.sdpMLineIndex)
            }
            session.iceFromSender.removeAll()
        } else {
            drained = session.iceFromReceiver.map {
                ARCPIceCandidateDto(candidate: $0.candidate, sdpMid: $0.sdpMid, sdpMLineIndex: $0.sdpMLineIndex)
            }
            session.iceFromReceiver.removeAll()
        }
        sessions[sessionId] = session
        lock.unlock()
        return HttpResponseBuilder.json(ARCPIceListResponse(candidates: drained), cors: true)
    }

    private func handleIcePost(body: String, query: [String: String]) -> String {
        guard let message = try? JSONDecoder().decode(ARCPIceMessage.self, from: Data(body.utf8)) else {
            return HttpResponseBuilder.response(status: 400, body: "Invalid JSON", contentType: "text/plain", cors: true)
        }
        let side = query["side"] ?? "sender"
        let candidate = IceCandidate(
            candidate: message.candidate,
            sdpMid: message.sdpMid,
            sdpMLineIndex: message.sdpMLineIndex
        )
        lock.lock()
        var session = sessions[message.sessionId] ?? SessionState()
        if side == "receiver" {
            session.iceFromReceiver.append(candidate)
        } else {
            session.iceFromSender.append(candidate)
        }
        sessions[message.sessionId] = session
        lock.unlock()
        return HttpResponseBuilder.json(["ok": true], cors: true)
    }

    private func handleStatus(query: [String: String]) -> String {
        let sessionId = query["sessionId"] ?? ""
        let state = locked { sessions[sessionId]?.state ?? "waiting" }
        return HttpResponseBuilder.json(ARCPStatusResponse(state: state), cors: true)
    }

    // MARK: - Helpers

    private func locked<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}
