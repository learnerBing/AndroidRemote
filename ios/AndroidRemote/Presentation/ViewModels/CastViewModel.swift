import SwiftUI

@MainActor
final class CastViewModel: ObservableObject {
    @Published var devices: [CastDevice] = []
    @Published var selectedDevice: CastDevice?
    @Published var pairingCode: String = ""
    @Published var connectionState: ConnectionState = .idle
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var pairedTVName: String?
    @Published var castSdkReady: Bool = false
    @Published var receivedTvCode: String?

    var canStartCasting: Bool {
        guard selectedDevice != nil else { return false }
        if selectedDevice?.isChromecast == true {
            return true
        }
        return pairingCode.count == 6
    }

    private let discoverDevices = DiscoverDevicesUseCase(repository: CompositeDeviceDiscovery())
    private let signaling = SignalingClient()
    private let sessionRepository = ScreenCastSessionRepositoryImpl()
    private let castSession: CastSessionManaging = CastSessionManager.shared

    private lazy var wiredPairDevice = PairDeviceUseCase(
        signaling: signaling,
        sessionStore: sessionRepository
    )

    private lazy var wiredPairCastDevice = PairCastDeviceUseCase(
        castSession: castSession,
        sessionStore: sessionRepository
    )

    private lazy var observeStatus = ObserveCastStatusUseCase(
        signaling: signaling,
        sessionStore: sessionRepository
    )

    private var discoveryTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var pairingPollTask: Task<Void, Never>?

    func onAppear() {
        castSdkReady = castSession.isCastSdkAvailable()
        discoveryTask = Task {
            await discoverDevices.start()
            for await found in discoverDevices.execute() {
                devices = found
                if connectionState == .discovering || connectionState == .idle {
                    connectionState = found.isEmpty ? .discovering : .idle
                }
            }
        }
        listenForCastPairingCodes()
    }

    func onDisappear() {
        discoveryTask?.cancel()
        statusTask?.cancel()
        pairingPollTask?.cancel()
        discoverDevices.stop()
    }

    func selectDevice(_ device: CastDevice) {
        selectedDevice = device
        connectionState = .pairing
        receivedTvCode = nil
        if device.isChromecast {
            pairingCode = ""
        }
    }

    func startCast() {
        guard let device = selectedDevice else { return }
        if !device.isChromecast && pairingCode.count != 6 { return }

        connectionState = .connecting
        errorMessage = nil

        Task {
            do {
                if device.isChromecast {
                    let code = pairingCode.isEmpty ? (receivedTvCode ?? "") : pairingCode
                    let session = try await wiredPairCastDevice.execute(device: device, pairingCode: code)
                    pairedTVName = device.name
                    pairingCode = session.pairingCode
                    startStatusPolling()
                } else {
                    let session = try await wiredPairDevice.execute(device: device, pairingCode: pairingCode)
                    pairedTVName = device.name
                    startStatusPolling()
                    _ = session
                }
            } catch {
                let message = error.localizedDescription
                connectionState = selectedDevice != nil ? .pairing : .idle
                errorMessage = message
                showError = true
            }
        }
    }

    func cancelConnecting() {
        statusTask?.cancel()
        castSession.endSession()
        connectionState = selectedDevice != nil ? .pairing : .idle
    }

    func dismissError() {
        showError = false
        errorMessage = nil
        if case .error = connectionState {
            connectionState = selectedDevice != nil ? .pairing : .idle
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

    private func listenForCastPairingCodes() {
        pairingPollTask?.cancel()
        pairingPollTask = Task {
            while !Task.isCancelled {
                if let code = castSession.latestPairingCode() {
                    receivedTvCode = code
                    if selectedDevice?.isChromecast == true, pairingCode.isEmpty {
                        pairingCode = code
                    }
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func resetSession() {
        statusTask?.cancel()
        castSession.endSession()
        SessionStore.clear()
        connectionState = .idle
        pairingCode = ""
        pairedTVName = nil
        receivedTvCode = nil
    }
}
