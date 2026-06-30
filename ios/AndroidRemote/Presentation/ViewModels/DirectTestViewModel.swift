import SwiftUI

@MainActor
final class DirectTestViewModel: ObservableObject {
    @Published var pairingCode: String = ""
    @Published var iphoneIP: String = ""
    @Published var receiverURL: String = TestReceiverConfig.defaultReceiverBaseURL
    @Published var connectionState: ConnectionState = .idle
    @Published var coordinatorRunning = false
    @Published var errorMessage: String?
    @Published var showError = false

    var canLink: Bool {
        pairingCode.count == 6 && coordinatorRunning && iphoneIP.isEmpty == false
    }

    var receiverURLWithIP: String {
        guard !iphoneIP.isEmpty else { return receiverURL }
        let base = receiverURL.split(separator: "?").first.map(String.init) ?? receiverURL
        return "\(base)?iphone=\(iphoneIP)"
    }

    private let coordinator = TestCoordinatorServer()
    private let sessionRepository = ScreenCastSessionRepositoryImpl()
    private let signaling = SignalingClient()

    private lazy var pairDirect = PairDirectWebReceiverUseCase(
        coordinator: coordinator,
        sessionStore: sessionRepository
    )

    private lazy var observeStatus = ObserveCastStatusUseCase(
        signaling: signaling,
        sessionStore: sessionRepository
    )

    private var statusTask: Task<Void, Never>?

    func onAppear() {
        refreshNetworkInfo()
        startCoordinator()
    }

    func onDisappear() {
        statusTask?.cancel()
        coordinator.stop()
        coordinatorRunning = false
    }

    func refreshNetworkInfo() {
        iphoneIP = LanAddress.currentWiFiIPv4() ?? "Unavailable — connect to Wi‑Fi"
    }

    func linkReceiver() {
        guard canLink else { return }
        connectionState = .connecting
        errorMessage = nil

        do {
            _ = try pairDirect.execute(pairingCode: pairingCode)
            startStatusPolling()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            connectionState = .idle
        }
    }

    func cancelConnecting() {
        statusTask?.cancel()
        connectionState = .idle
    }

    func resetSession() {
        statusTask?.cancel()
        coordinator.clearLink(code: pairingCode)
        SessionStore.clear()
        connectionState = .idle
        pairingCode = ""
    }

    func dismissError() {
        showError = false
        errorMessage = nil
    }

    private func startCoordinator() {
        do {
            try coordinator.start()
            coordinatorRunning = true
        } catch {
            coordinatorRunning = false
            errorMessage = "Could not start test server on port \(TestReceiverConfig.coordinatorPort)"
            showError = true
        }
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
