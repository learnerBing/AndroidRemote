import Foundation

/// POST pairing link to Mac LAN relay (iPhone → outbound only).
struct RelayLinkClient {
    func checkRelayReachable(relayHost: String, relayPort: Int) async throws {
        ARLog.info("Relay", "health check http://\(relayHost):\(relayPort)/health")
        guard let url = URL(string: "http://\(relayHost):\(relayPort)/health") else {
            throw CastError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                ARLog.error("Relay", "health check failed HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw CastError.discoveryFailed
            }
            ARLog.info("Relay", "health check OK")
        } catch is CastError {
            throw CastError.discoveryFailed
        } catch {
            ARLog.error("Relay", "health check error=\(error.localizedDescription)")
            throw CastError.discoveryFailed
        }
    }

    func fetchActiveCode(relayHost: String, relayPort: Int, maxAttempts: Int = 30) async throws -> String {
        ARLog.info("Relay", "fetchActiveCode from http://\(relayHost):\(relayPort)/test/active-code")
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
                    if attempt == 0 || attempt % 10 == 9 {
                        ARLog.warn("Relay", "active-code 204 attempt=\(attempt + 1) — open test-receiver.html on Mac")
                    }
                    try await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
                guard http.statusCode == 200, !data.isEmpty else {
                    throw CastError.discoveryFailed
                }
                struct ActiveCodeResponse: Decodable { let code: String }
                let decoded = try JSONDecoder().decode(ActiveCodeResponse.self, from: data)
                guard decoded.code.count == 6 else { throw CastError.discoveryFailed }
                ARLog.info("Relay", "active-code=\(decoded.code)")
                return decoded.code
            } catch let error as CastError {
                throw error
            } catch {
                throw CastError.discoveryFailed
            }
        }
        if lastWasEmpty {
            ARLog.error("Relay", "browser not open — no active code after \(maxAttempts) attempts")
            throw CastError.relayBrowserNotOpen
        }
        throw CastError.discoveryFailed
    }

    func registerLink(relayHost: String, relayPort: Int, code: String, sessionId: String) async throws {
        ARLog.info("Relay", "registerLink code=\(code) session=\(ARLog.sessionPrefix(sessionId)) → http://\(relayHost):\(relayPort)/test/link")
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
                ARLog.error("Relay", "registerLink failed HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                throw CastError.discoveryFailed
            }
            ARLog.info("Relay", "registerLink OK code=\(code) session=\(ARLog.sessionPrefix(sessionId))")
        } catch is CastError {
            throw CastError.discoveryFailed
        } catch {
            ARLog.error("Relay", "registerLink error=\(error.localizedDescription)")
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
            ARLog.error("Relay", "invalid relay \(relayHost):\(relayPort)")
            throw CastError.notConfigured
        }
        if relayHost == "127.0.0.1" || relayHost == "localhost" {
            ARLog.error("Relay", "127.0.0.1 is Mac-only — use Mac LAN IP on iPhone (e.g. 192.168.x.x)")
        }

        try await relayClient.checkRelayReachable(relayHost: relayHost, relayPort: relayPort)

        let code: String
        if let pairingCode, pairingCode.count == 6, pairingCode.allSatisfy(\.isNumber) {
            code = pairingCode
            ARLog.info("Relay", "using provided code=\(code)")
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

        ARLog.info("Relay", "pair complete code=\(code) session=\(ARLog.sessionPrefix(sessionId)) — start broadcast")
        return PairingSession(
            sessionId: sessionId,
            pairingCode: code,
            expiresAt: Date().addingTimeInterval(300)
        )
    }
}
