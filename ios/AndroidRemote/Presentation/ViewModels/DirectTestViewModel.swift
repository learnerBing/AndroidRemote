import SwiftUI

@MainActor
final class DirectTestViewModel: ObservableObject {
    @Published var detectedCode: String?
    @Published var relayHost: String = ""
    @Published var relayPort: String = "8080"
    @Published var connectionState: ConnectionState = .idle
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var broadcastActive = false
    @Published var relayStatus: String = "waiting"

    var canLink: Bool {
        LanAddress.isValidIPv4(relayHost) && (Int(relayPort) ?? 0) > 0
    }

    var receiverPageURL: String {
        guard LanAddress.isValidIPv4(relayHost), let port = Int(relayPort), port > 0 else {
            return "http://MAC_IP:8080/test-receiver.html"
        }
        return "http://\(relayHost):\(port)/test-receiver.html"
    }

    private let sessionRepository = ScreenCastSessionRepositoryImpl()
    private let signaling = SignalingClient()
    private let relayClient = RelayLinkClient()

    private lazy var pairDirect = PairDirectWebReceiverUseCase(
        relayClient: relayClient,
        sessionStore: sessionRepository
    )

    private var statusTask: Task<Void, Never>?
    private var broadcastStartedObserver: DarwinObserver?
    private var broadcastFailedObserver: DarwinObserver?
    private var broadcastFinishedObserver: DarwinObserver?

    func onAppear() {
        if relayHost.isEmpty {
            relayHost = UserDefaults.standard.string(forKey: "test.relayHost") ?? ""
        }
        broadcastStartedObserver = BroadcastNotification.observeStarted { [weak self] in
            Task { @MainActor in
                self?.broadcastActive = true
                self?.evaluateStreamingState()
            }
        }
        broadcastFailedObserver = BroadcastNotification.observeFailed { [weak self] in
            Task { @MainActor in
                self?.broadcastActive = false
                let hint = SessionStore.load() == nil
                    ? "No linked session in App Group. Tap Link Receiver and wait for the code to appear, then start broadcast from the in-app button (not Control Center)."
                    : "Broadcast failed. Link Receiver again, then start broadcast from the in-app button below (not Control Center)."
                self?.errorMessage = hint
                self?.showError = true
            }
        }
        broadcastFinishedObserver = BroadcastNotification.observeFinished { [weak self] in
            Task { @MainActor in
                self?.broadcastActive = false
                if self?.connectionState == .streaming {
                    self?.connectionState = .connecting
                }
            }
        }
    }

    func onDisappear() {
        statusTask?.cancel()
        broadcastStartedObserver = nil
        broadcastFailedObserver = nil
        broadcastFinishedObserver = nil
    }

    func linkReceiver() {
        guard canLink, let port = Int(relayPort) else { return }
        ARLog.info("Test", "linkReceiver relay=\(relayHost):\(port)")
        connectionState = .connecting
        errorMessage = nil
        broadcastActive = false
        UserDefaults.standard.set(relayHost, forKey: "test.relayHost")

        Task {
            let previous = SessionStore.load()
            do {
                let session = try await pairDirect.execute(
                    relayHost: relayHost,
                    relayPort: port
                )
                guard SessionStore.load() != nil else {
                    throw CastError.notConfigured
                }
                if let previous, previous.sessionId != session.sessionId {
                    let endSignaling = SignalingClient()
                    endSignaling.bind(snapshot: previous)
                    try? await endSignaling.updateSessionStatus(sessionId: previous.sessionId, state: "ended")
                }
                detectedCode = session.pairingCode
                ARLog.configureRelay(host: relayHost, port: port, sessionId: session.sessionId)
                ARLog.info("Test", "linked code=\(session.pairingCode) session=\(ARLog.sessionPrefix(session.sessionId))")
                broadcastActive = false
                startStatusPolling()
            } catch {
                ARLog.error("Test", "link failed: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                connectionState = .idle
            }
        }
    }

    func cancelConnecting() {
        statusTask?.cancel()
        connectionState = .idle
    }

    func resetSession() {
        statusTask?.cancel()
        if let snapshot = SessionStore.load() {
            let signaling = SignalingClient()
            signaling.bind(snapshot: snapshot)
            Task {
                try? await signaling.updateSessionStatus(sessionId: snapshot.sessionId, state: "ended")
            }
        }
        SessionStore.clear()
        ARLog.clearRelay()
        broadcastActive = false
        connectionState = .idle
        detectedCode = nil
    }

    func dismissError() {
        showError = false
        errorMessage = nil
    }

    private func startStatusPolling() {
        statusTask?.cancel()
        statusTask = Task {
            await pollUntilLive()
        }
    }

    /// Live UI requires broadcast extension running AND relay ICE connected (not browser SDP alone).
    private func pollUntilLive() async {
        guard let snapshot = sessionRepository.loadSession() else { return }
        signaling.bind(snapshot: snapshot)
        ARLog.info("Test", "polling for live session=\(ARLog.sessionPrefix(snapshot.sessionId))")
        var lastStatus = ""
        for _ in 0..<240 {
            if Task.isCancelled { return }
            let status = (try? await signaling.pollStatus(sessionId: snapshot.sessionId)) ?? "waiting"
            relayStatus = status
            if status != lastStatus {
                ARLog.info("Test", "status=\(status) session=\(ARLog.sessionPrefix(snapshot.sessionId))")
                lastStatus = status
            }
            if status == "broadcasting" || status == "connecting" {
                broadcastActive = true
            }
            if status == "connected", broadcastActive {
                connectionState = .streaming
                return
            }
            if status == "ended" || status == "disconnected" {
                connectionState = .idle
                broadcastActive = false
                errorMessage = "Broadcast ended on relay (\(status)). Tap Link Receiver, hard-refresh the browser tab, then start broadcast again."
                showError = true
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        ARLog.warn("Test", "pollUntilLive timeout session=\(ARLog.sessionPrefix(snapshot.sessionId))")
    }

    private func evaluateStreamingState() {
        guard broadcastActive, connectionState == .connecting,
              let snapshot = sessionRepository.loadSession() else { return }
        Task {
            signaling.bind(snapshot: snapshot)
            let status = (try? await signaling.pollStatus(sessionId: snapshot.sessionId)) ?? ""
            if status == "connected" {
                connectionState = .streaming
            }
        }
    }

    var linkedSessionId: String? {
        SessionStore.load()?.sessionId
    }
}
