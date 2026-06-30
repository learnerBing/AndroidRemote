import Foundation

/// POST pairing link to Mac LAN relay (iPhone → outbound only).
struct RelayLinkClient {
    func checkRelayReachable(relayHost: String, relayPort: Int) async throws {
        guard let url = URL(string: "http://\(relayHost):\(relayPort)/health") else {
            throw CastError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw CastError.discoveryFailed
            }
        } catch is CastError {
            throw CastError.discoveryFailed
        } catch {
            throw CastError.discoveryFailed
        }
    }

    func fetchActiveCode(relayHost: String, relayPort: Int, maxAttempts: Int = 30) async throws -> String {
        guard let url = URL(string: "http://\(relayHost):\(relayPort)/test/active-code") else {
            throw CastError.notConfigured
        }

        var lastWasEmpty = false
        for attempt in 0..<maxAttempts {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 5
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw CastError.discoveryFailed
                }
                if http.statusCode == 204 {
                    lastWasEmpty = true
                    try await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                guard http.statusCode == 200, !data.isEmpty else {
                    throw CastError.discoveryFailed
                }
                struct ActiveCodeResponse: Decodable { let code: String }
                let decoded = try JSONDecoder().decode(ActiveCodeResponse.self, from: data)
                guard decoded.code.count == 6 else { throw CastError.discoveryFailed }
                return decoded.code
            } catch let error as CastError {
                throw error
            } catch {
                throw CastError.discoveryFailed
            }
        }
        if lastWasEmpty {
            throw CastError.relayBrowserNotOpen
        }
        throw CastError.discoveryFailed
    }

    func registerLink(relayHost: String, relayPort: Int, code: String, sessionId: String) async throws {
        guard let url = URL(string: "http://\(relayHost):\(relayPort)/test/link") else {
            throw CastError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5
        let body: [String: String] = ["code": code, "sessionId": sessionId]
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CastError.discoveryFailed
            }
        } catch is CastError {
            throw CastError.discoveryFailed
        } catch {
            throw CastError.discoveryFailed
        }
    }
}

/// Direct LAN test: link via Mac relay (no inbound TCP to iPhone).
struct PairDirectWebReceiverUseCase {
    let relayClient: RelayLinkClient
    let sessionStore: ScreenCastSessionRepository

    init(relayClient: RelayLinkClient = RelayLinkClient(), sessionStore: ScreenCastSessionRepository) {
        self.relayClient = relayClient
        self.sessionStore = sessionStore
    }

    func execute(relayHost: String, relayPort: Int, pairingCode: String? = nil) async throws -> PairingSession {
        guard LanAddress.isValidIPv4(relayHost), relayPort > 0 else {
            throw CastError.notConfigured
        }

        try await relayClient.checkRelayReachable(relayHost: relayHost, relayPort: relayPort)

        let code: String
        if let pairingCode, pairingCode.count == 6, pairingCode.allSatisfy(\.isNumber) {
            code = pairingCode
        } else {
            code = try await relayClient.fetchActiveCode(relayHost: relayHost, relayPort: relayPort)
        }

        let sessionId = UUID().uuidString
        try await relayClient.registerLink(
            relayHost: relayHost,
            relayPort: relayPort,
            code: code,
            sessionId: sessionId
        )

        let device = CastDevice(
            id: "web-receiver-test",
            name: "Web Receiver (Test)",
            kind: .chromecast
        )
        sessionStore.saveDirectTestSession(
            sessionId: sessionId,
            device: device,
            relayHost: relayHost,
            relayPort: relayPort
        )

        return PairingSession(
            sessionId: sessionId,
            pairingCode: code,
            expiresAt: Date().addingTimeInterval(300)
        )
    }
}
