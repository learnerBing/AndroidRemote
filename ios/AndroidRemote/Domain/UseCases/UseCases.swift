import Foundation

// MARK: - Use Cases

struct DiscoverDevicesUseCase {
    let repository: DeviceDiscoveryRepository

    func execute() -> AsyncStream<[CastDevice]> {
        repository.discoveredDevices
    }

    func start() async {
        await repository.startBrowsing()
    }

    func stop() {
        repository.stopBrowsing()
    }
}

/// V1: Pair with native Android TV via HTTP signaling on the TV.
struct PairDeviceUseCase {
    let signaling: SignalingClientRepository
    let sessionStore: ScreenCastSessionRepository

    func execute(device: CastDevice, pairingCode: String) async throws -> PairingSession {
        signaling.bind(device: device)
        let session = try await signaling.pair(code: pairingCode)
        sessionStore.savePairedSession(session, device: device)
        return session
    }
}

/// V1 Cast-first: launch web receiver, exchange code, point TV at iPhone signaling.
struct PairCastDeviceUseCase {
    let castSession: CastSessionManaging
    let sessionStore: ScreenCastSessionRepository

    func execute(device: CastDevice, pairingCode: String) async throws -> PairingSession {
        try await castSession.connect(to: device)

        let expectedCode = try await waitForPairingCode(timeoutSeconds: 15)
        guard pairingCode.isEmpty || pairingCode == expectedCode else {
            throw CastError.invalidPairingCode
        }

        guard let host = LanAddress.currentWiFiIPv4() else {
            throw CastError.lanAddressUnavailable
        }

        let sessionId = UUID().uuidString
        try await castSession.sendSessionPrepare(
            sessionId: sessionId,
            host: host,
            port: CastConfig.signalingPort
        )

        let session = PairingSession(
            sessionId: sessionId,
            pairingCode: expectedCode,
            expiresAt: Date().addingTimeInterval(300)
        )
        sessionStore.saveCastSession(sessionId: sessionId, device: device, signalingHost: host)
        return session
    }

    private func waitForPairingCode(timeoutSeconds: Int) async throws -> String {
        for _ in 0..<(timeoutSeconds * 2) {
            if let code = castSession.latestPairingCode() {
                return code
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw CastError.answerTimeout
    }
}

struct ObserveCastStatusUseCase {
    let signaling: SignalingClient
    let sessionStore: ScreenCastSessionRepository

    func pollUntilConnected(timeoutSeconds: Int = 120) async throws -> Bool {
        guard let snapshot = sessionStore.loadSession() else { return false }
        signaling.bind(snapshot: snapshot)
        for _ in 0..<(timeoutSeconds * 2) {
            let status = try await signaling.pollStatus(sessionId: snapshot.sessionId)
            if status == "connected" { return true }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }
}

struct ClearCastSessionUseCase {
    let sessionStore: ScreenCastSessionRepository

    func execute() {
        sessionStore.clearSession()
    }
}
