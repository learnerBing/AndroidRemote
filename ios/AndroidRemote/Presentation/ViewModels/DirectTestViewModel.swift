import SwiftUI

@MainActor
final class DirectTestViewModel: ObservableObject {
    @Published var detectedCode: String?
    @Published var relayHost: String = ""
    @Published var relayPort: String = "8080"
    @Published var connectionState: ConnectionState = .idle
    @Published var errorMessage: String?
    @Published var showError = false

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

    private lazy var observeStatus = ObserveCastStatusUseCase(
        signaling: signaling,
        sessionStore: sessionRepository
    )

    private var statusTask: Task<Void, Never>?

    func onAppear() {
        if relayHost.isEmpty {
            relayHost = UserDefaults.standard.string(forKey: "test.relayHost") ?? ""
        }
    }

    func onDisappear() {
        statusTask?.cancel()
    }

    func linkReceiver() {
        guard canLink, let port = Int(relayPort) else { return }
        connectionState = .connecting
        errorMessage = nil
        UserDefaults.standard.set(relayHost, forKey: "test.relayHost")

        Task {
            do {
                let session = try await pairDirect.execute(
                    relayHost: relayHost,
                    relayPort: port
                )
                detectedCode = session.pairingCode
                startStatusPolling()
            } catch {
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
            let connected = (try? await observeStatus.pollUntilConnected()) ?? false
            if connected {
                connectionState = .streaming
            } else if !Task.isCancelled {
                connectionState = .connecting
            }
        }
    }
}
