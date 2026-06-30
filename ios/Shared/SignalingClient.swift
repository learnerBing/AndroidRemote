import Foundation

/// HTTP client for ARCP signaling (include in main app + broadcast extension targets).
final class SignalingClient: @unchecked Sendable {
    private let session: URLSession
    private var tvHost: String?
    private var tvPort: Int?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func bind(host: String, port: Int) {
        tvHost = host
        tvPort = port
    }

    func bind(device: CastDevice) {
        bind(host: device.host, port: device.port)
    }

    func bind(snapshot: SessionStore.Snapshot) {
        bind(host: snapshot.tvHost, port: snapshot.tvPort)
    }

    // MARK: - Pairing

    func pair(code: String) async throws -> PairingSession {
        let url = try endpoint("pair")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ARCPPairRequest(code: code))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw CastError.invalidPairingCode
        }
        let pairResponse = try JSONDecoder().decode(ARCPPairResponse.self, from: data)
        return PairingSession(
            sessionId: pairResponse.sessionId,
            pairingCode: code,
            expiresAt: Date().addingTimeInterval(300)
        )
    }

    // MARK: - SDP

    func sendOffer(sessionId: String, sdp: String) async throws {
        try await postSdp(sessionId: sessionId, type: "offer", sdp: sdp)
    }

    func pollAnswer(sessionId: String, maxAttempts: Int = 40) async throws -> String {
        for _ in 0..<maxAttempts {
            if let answer = try await fetchAnswer(sessionId: sessionId) {
                return answer
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw CastError.answerTimeout
    }

    private func fetchAnswer(sessionId: String) async throws -> String? {
        var components = URLComponents(url: try endpoint("sdp"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 204 || data.isEmpty { return nil }
        guard http.statusCode == 200 else { return nil }
        let message = try JSONDecoder().decode(ARCPSdpMessage.self, from: data)
        return message.sdp
    }

    private func postSdp(sessionId: String, type: String, sdp: String) async throws {
        let url = try endpoint("sdp")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ARCPSdpMessage(sessionId: sessionId, type: type, sdp: sdp)
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CastError.notConfigured
        }
    }

    // MARK: - ICE

    func sendIceCandidate(sessionId: String, candidate: IceCandidate) async throws {
        let url = try endpoint("ice")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ARCPIceMessage(
            sessionId: sessionId,
            candidate: candidate.candidate,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        request.httpBody = try JSONEncoder().encode(body)
        _ = try await session.data(for: request)
    }

    func pollRemoteIceCandidates(sessionId: String) async throws -> [IceCandidate] {
        var components = URLComponents(url: try endpoint("ice"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        let list = try JSONDecoder().decode(ARCPIceListResponse.self, from: data)
        return list.candidates.map {
            IceCandidate(candidate: $0.candidate, sdpMid: $0.sdpMid, sdpMLineIndex: $0.sdpMLineIndex)
        }
    }

    // MARK: - Status

    func pollStatus(sessionId: String) async throws -> String {
        var components = URLComponents(url: try endpoint("status"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId)]
        guard let url = components.url else { return "waiting" }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return "waiting" }
        let status = try JSONDecoder().decode(ARCPStatusResponse.self, from: data)
        return status.state
    }

    // MARK: - Private

    private func endpoint(_ path: String) throws -> URL {
        guard let host = tvHost, let port = tvPort else { throw CastError.notConfigured }
        guard let url = URL(string: "http://\(host):\(port)/\(path)") else {
            throw CastError.notConfigured
        }
        return url
    }
}

