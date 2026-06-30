import SwiftUI

@MainActor
final class DirectTestViewModel: ObservableObject {
    @Published var pairingCode: String = ""
    @Published var iphoneIP: String = ""
    @Published var localReceiverBaseURL: String = ""
    @Published var receiverURL: String = TestReceiverConfig.defaultReceiverBaseURL
    @Published var connectionState: ConnectionState = .idle
    @Published var coordinatorRunning = false
    @Published var localHealthOK = false
    @Published var localNetworkHint: String?
    @Published var errorMessage: String?
    @Published var showError = false

    var canLink: Bool {
        pairingCode.count == 6 && coordinatorRunning && LanAddress.isValidIPv4(iphoneIP)
    }

    var receiverURLWithIP: String {
        let base: String
        if !localReceiverBaseURL.trimmingCharacters(in: .whitespaces).isEmpty {
            base = localReceiverBaseURL.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            base = receiverURL.split(separator: "?").first.map(String.init) ?? receiverURL
        }
        guard LanAddress.isValidIPv4(iphoneIP) else { return base }
        return "\(base)?iphone=\(iphoneIP)"
    }

    private let coordinatorService = TestCoordinatorService.shared
    private let sessionRepository = ScreenCastSessionRepositoryImpl()
    private let signaling = SignalingClient()

    private lazy var pairDirect = PairDirectWebReceiverUseCase(
        coordinator: coordinatorService.server,
        sessionStore: sessionRepository
    )

    private lazy var observeStatus = ObserveCastStatusUseCase(
        signaling: signaling,
        sessionStore: sessionRepository
    )

    private var statusTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?

    func onAppear() {
        refreshNetworkInfo()
        LocalNetworkAuthorization.shared.requestAuthorization()
        startCoordinator()
        startHealthPolling()
    }

    func onDisappear() {
        statusTask?.cancel()
        healthTask?.cancel()
        // Keep coordinator running — browser on TV/Mac must reach iPhone while testing.
    }

    func refreshNetworkInfo() {
        iphoneIP = LanAddress.currentWiFiIPv4() ?? ""
        if iphoneIP.isEmpty {
            localNetworkHint = "No Wi‑Fi IP found. Connect to Wi‑Fi and tap Refresh."
            coordinatorRunning = false
        } else {
            startCoordinator()
        }
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
        coordinatorService.server.clearLink(code: pairingCode)
        SessionStore.clear()
        connectionState = .idle
        pairingCode = ""
    }

    func stopTestServer() {
        resetSession()
        healthTask?.cancel()
        coordinatorService.stop()
        coordinatorRunning = false
        localHealthOK = false
    }

    func dismissError() {
        showError = false
        errorMessage = nil
    }

    private func startCoordinator() {
        guard LanAddress.isValidIPv4(iphoneIP) else {
            coordinatorRunning = false
            localNetworkHint = "Connect to Wi‑Fi, allow Local Network when prompted, then tap Refresh."
            return
        }
        do {
            try coordinatorService.ensureStarted(advertisedIP: iphoneIP)
            coordinatorRunning = true
            localNetworkHint = "Keep this app in the foreground on the Test tab while pairing."
        } catch {
            coordinatorRunning = false
            errorMessage = "Could not start pairing server on port \(TestReceiverConfig.coordinatorPort): \(error.localizedDescription)"
            showError = true
        }
    }

    private func startHealthPolling() {
        healthTask?.cancel()
        healthTask = Task {
            while !Task.isCancelled {
                if LanAddress.isValidIPv4(iphoneIP) {
                    let ok = await CoordinatorHealthCheck.check(host: iphoneIP)
                    localHealthOK = ok
                    if !ok && coordinatorRunning {
                        localNetworkHint = "Other devices cannot reach this iPhone yet. Allow Local Network in Settings → AndroidRemote, disable VPN, and ensure router client isolation is off."
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
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
