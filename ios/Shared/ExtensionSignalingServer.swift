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
        receiveRequest(on: connection, buffer: Data())
    }

    /// A single `receive()` call is not guaranteed to deliver the full HTTP request — headers
    /// and body can arrive in separate reads under load (e.g. the receiver's 300ms ICE polling
    /// racing the extension's own outgoing ICE posts). Accumulate until we have complete headers
    /// and, per Content-Length, the complete body before routing — otherwise POSTs get routed on
    /// a truncated body and fail JSON decoding with a spurious 400.
    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data, !data.isEmpty {
                buffer.append(data)
            }
            if let request = self.completeRequest(from: buffer) {
                let response = self.route(request)
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, buffer: buffer)
        }
    }

    /// Returns the full request text once headers and (per Content-Length) the full body have
    /// arrived; nil while more data is still expected.
    private func completeRequest(from buffer: Data) -> String? {
        guard let raw = String(data: buffer, encoding: .utf8) else { return nil }
        guard let headerEnd = raw.range(of: "\r\n\r\n") ?? raw.range(of: "\n\n") else {
            return nil
        }
        let headerText = raw[raw.startIndex..<headerEnd.lowerBound]
        let bodySoFar = raw[headerEnd.upperBound...]
        let contentLength = parseContentLength(headerText)

        guard bodySoFar.utf8.count >= contentLength else { return nil }
        return raw
    }

    /// Parses the Content-Length header value out of raw header text.
    ///
    /// Swift treats "\r\n" as a *single* extended grapheme Character, not two — every real HTTP
    /// request uses CRLF line endings, so `split(separator: "\n")` (a bare LF Character) never
    /// finds a split point at all and silently returns the whole header block as one element,
    /// which never has the "content-length:" prefix. That made this return 0 unconditionally,
    /// which in turn made `completeRequest` below treat the request as "complete" the instant
    /// headers arrived — before the body necessarily had, which is what actually produced the
    /// intermittent bytes=0 decode failures blamed (across several prior fixes) on concurrency.
    /// Splitting on "\r\n" as its own Character literal (valid in Swift — CRLF is a recognized
    /// grapheme-cluster exception) matches how lines are actually delimited on the wire.
    private func parseContentLength(_ headerText: Substring) -> Int {
        headerText
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
    }

    private func route(_ raw: String) -> String {
        // Same CRLF-as-one-Character caveat as parseContentLength above.
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)
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

        // Cap the body to exactly Content-Length bytes. The client (URLSession.shared, shared
        // across every SignalingClient call) can dispatch its next request onto the same
        // connection before this one is fully torn down despite our "Connection: close" —
        // taking "everything remaining in the buffer" as the body then appends the start of
        // that next request, and JSONDecoder rejects the trailing garbage as invalid JSON.
        let body: String
        // Diagnostic snapshot of what we actually parsed off the wire for this request, so a
        // decode failure below can tell us whether Content-Length was missing/zero (client didn't
        // declare a body length we understood) vs. present-but-body-truncated (our own buffering
        // is still short) instead of guessing from bytes=0 alone.
        let requestDiagnostic: String
        if let headerEnd = raw.range(of: "\r\n\r\n") ?? raw.range(of: "\n\n") {
            let headerText = raw[raw.startIndex..<headerEnd.lowerBound]
            let contentLength = parseContentLength(headerText)
            let rawBody = raw[headerEnd.upperBound...]
            body = contentLength > 0
                ? String(decoding: Array(rawBody.utf8.prefix(contentLength)), as: UTF8.self)
                : String(rawBody)
            requestDiagnostic = "contentLength=\(contentLength) rawBodyBytes=\(rawBody.utf8.count) " +
                "headers=\(headerText.replacingOccurrences(of: "\r\n", with: "|"))"
        } else {
            body = ""
            requestDiagnostic = "no header terminator found in \(raw.utf8.count) raw bytes"
        }

        switch (method, path) {
        case ("GET", "/health"):
            return HttpResponseBuilder.json(ARCPHealthResponse(ok: true), cors: true)
        case ("GET", "/sdp/offer"):
            return handleOfferGet(query: query)
        case ("GET", "/sdp"):
            return handleAnswerGet(query: query)
        case ("POST", "/sdp"):
            return handleSdpPost(body: body, diagnostic: requestDiagnostic)
        case ("GET", "/ice"):
            return handleIceGet(query: query)
        case ("POST", "/ice"):
            return handleIcePost(body: body, query: query, diagnostic: requestDiagnostic)
        case ("GET", "/status"):
            return handleStatus(query: query)
        case ("POST", "/status"):
            return handleStatusPost(body: body)
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

    private func handleSdpPost(body: String, diagnostic: String) -> String {
        do {
            let message = try JSONDecoder().decode(ARCPSdpMessage.self, from: Data(body.utf8))
            return respondToSdpPost(message)
        } catch {
            ARLog.error(
                "Signaling",
                "POST /sdp decode failed: \(error.localizedDescription) bytes=\(body.utf8.count) " +
                "prefix=\(body.prefix(80)) suffix=\(body.suffix(80)) [\(diagnostic)]"
            )
            return HttpResponseBuilder.response(status: 400, body: "Invalid JSON", contentType: "text/plain", cors: true)
        }
    }

    private func respondToSdpPost(_ message: ARCPSdpMessage) -> String {
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

    private func handleIcePost(body: String, query: [String: String], diagnostic: String) -> String {
        let message: ARCPIceMessage
        do {
            message = try JSONDecoder().decode(ARCPIceMessage.self, from: Data(body.utf8))
        } catch {
            ARLog.error(
                "Signaling",
                "POST /ice decode failed: \(error.localizedDescription) bytes=\(body.utf8.count) " +
                "prefix=\(body.prefix(80)) suffix=\(body.suffix(80)) [\(diagnostic)]"
            )
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

    /// SignalingClient.updateSessionStatus posts here (sessionId/state JSON body) — there was no
    /// handler for it at all, so every call got a 404. Harmless in practice since every call
    /// site uses `try?`, but the state update itself was silently dropped.
    private func handleStatusPost(body: String) -> String {
        struct Body: Decodable {
            let sessionId: String
            let state: String
        }
        guard let message = try? JSONDecoder().decode(Body.self, from: Data(body.utf8)) else {
            return HttpResponseBuilder.response(status: 400, body: "Invalid JSON", contentType: "text/plain", cors: true)
        }
        updateConnectionState(message.sessionId, state: message.state)
        return HttpResponseBuilder.json(["ok": true], cors: true)
    }

    // MARK: - Helpers

    private func locked<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}
