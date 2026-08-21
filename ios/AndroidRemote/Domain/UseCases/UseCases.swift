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

    /// Chromecast pairing never has a user-typed code to validate — MirrorHomeView shows no
    /// entry field for isChromecast devices, the code is always auto-received over the trusted
    /// Cast custom-message channel and just displayed. Comparing it against itself was a no-op
    /// on a first attempt, but on a retry `connect(to:)` tears down a stale session and the TV
    /// relaunches the receiver fresh with a brand-new code — while the caller's `pairingCode`
    /// still held the old one from the first attempt, so this used to reject the retry outright.
    func execute(device: CastDevice) async throws -> PairingSession {
        try await castSession.connect(to: device)

        let expectedCode = try await waitForPairingCode(timeoutSeconds: 15)

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
        guard let snapshot = sessionStore.loadSession() else {
            ARLog.warn("Test", "pollUntilConnected — no session")
            return false
        }
        signaling.bind(snapshot: snapshot)
        ARLog.info("Test", "polling status session=\(ARLog.sessionPrefix(snapshot.sessionId))")
        var lastStatus = ""
        for i in 0..<(timeoutSeconds * 2) {
            let status = try await signaling.pollStatus(sessionId: snapshot.sessionId)
            if status != lastStatus {
                ARLog.info("Test", "status=\(status) session=\(ARLog.sessionPrefix(snapshot.sessionId))")
                lastStatus = status
            } else if i == 0 || i % 20 == 19 {
                ARLog.info("Test", "still status=\(status) poll=\(i + 1)")
            }
            if status == "connected" { return true }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        ARLog.warn("Test", "pollUntilConnected timeout session=\(ARLog.sessionPrefix(snapshot.sessionId))")
        return false
    }
}

struct ClearCastSessionUseCase {
    let sessionStore: ScreenCastSessionRepository

    func execute() {
        sessionStore.clearSession()
    }
}
