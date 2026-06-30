import Foundation
@preconcurrency import GoogleCast

/// Discovers Chromecast / Google TV devices via Google Cast SDK.
final class CastDeviceDiscovery: DeviceDiscoveryRepository {
    private let castSession: CastSessionManaging

    init(castSession: CastSessionManaging = CastSessionManager.shared) {
        self.castSession = castSession
    }

    var discoveredDevices: AsyncStream<[CastDevice]> {
        castSession.discoveredDevices
    }

    func startBrowsing() async {
        castSession.startDiscovery()
    }

    func stopBrowsing() {
        castSession.stopDiscovery()
    }
}

/// Browses native Android TV receivers via mDNS (optional secondary path).
final class CompositeDeviceDiscovery: DeviceDiscoveryRepository {
    private let castDiscovery: CastDeviceDiscovery
    private let mdnsDiscovery: MdnsBrowser
    private var continuation: AsyncStream<[CastDevice]>.Continuation?
    private var castDevices: [CastDevice] = []
    private var nativeDevices: [CastDevice] = []

    init(
        castDiscovery: CastDeviceDiscovery = CastDeviceDiscovery(),
        mdnsDiscovery: MdnsBrowser = MdnsBrowser()
    ) {
        self.castDiscovery = castDiscovery
        self.mdnsDiscovery = mdnsDiscovery
    }

    var discoveredDevices: AsyncStream<[CastDevice]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield([])
        }
    }

    func startBrowsing() async {
        await castDiscovery.startBrowsing()
        await mdnsDiscovery.startBrowsing()

        Task {
            for await devices in castDiscovery.discoveredDevices {
                castDevices = devices
                publish()
            }
        }
        Task {
            for await devices in mdnsDiscovery.discoveredDevices {
                nativeDevices = devices.map {
                    CastDevice(id: $0.id, name: $0.name, host: $0.host, port: $0.port, kind: .nativeTv)
                }
                publish()
            }
        }
    }

    func stopBrowsing() {
        castDiscovery.stopBrowsing()
        mdnsDiscovery.stopBrowsing()
        continuation?.finish()
    }

    private func publish() {
        continuation?.yield(castDevices + nativeDevices)
    }
}

final class CastSessionManager: NSObject, CastSessionManaging, @unchecked Sendable {
    static let shared = CastSessionManager()

    private var deviceContinuation: AsyncStream<[CastDevice]>.Continuation?
    private var devicesById: [String: GCKDevice] = [:]
    private var lastPairingCode: String?
    private let queue = DispatchQueue(label: "com.androidremote.cast-session")
    private let signalingChannel: GCKGenericChannel
    private var sessionStartContinuation: CheckedContinuation<Void, Error>?

    private override init() {
        signalingChannel = GCKGenericChannel(namespace: CastConfig.customChannel)
        super.init()
        signalingChannel.delegate = self
    }

    var discoveredDevices: AsyncStream<[CastDevice]> {
        AsyncStream { continuation in
            self.deviceContinuation = continuation
            continuation.yield(self.currentDevices())
        }
    }

    func latestPairingCode() -> String? {
        queue.sync { lastPairingCode }
    }

    func isCastSdkAvailable() -> Bool {
        CastConfig.receiverAppId != "YOUR_CAST_APP_ID"
    }

    func startDiscovery() {
        guard isCastSdkAvailable() else { return }
        let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
        discoveryManager.add(self)
        discoveryManager.startDiscovery()
        publishDevices()
    }

    func stopDiscovery() {
        guard isCastSdkAvailable() else { return }
        let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
        discoveryManager.stopDiscovery()
        discoveryManager.remove(self)
    }

    func connect(to device: CastDevice) async throws {
        guard isCastSdkAvailable() else { throw CastError.castSdkUnavailable }
        guard let gckDevice = devicesById[device.id] else { throw CastError.castSessionFailed }
        queue.sync { lastPairingCode = nil }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionStartContinuation = continuation
            DispatchQueue.main.async {
                let sessionManager = GCKCastContext.sharedInstance().sessionManager
                sessionManager.add(self)
                if !sessionManager.startSession(with: gckDevice) {
                    self.sessionStartContinuation = nil
                    continuation.resume(throwing: CastError.castSessionFailed)
                }
            }
        }
    }

    func sendSessionPrepare(sessionId: String, host: String, port: Int) async throws {
        let message = CastSignalingMessage.sessionPrepare(sessionId: sessionId, host: host, port: port)
        try sendCastMessage(message)
    }

    func endSession() {
        DispatchQueue.main.async {
            GCKCastContext.sharedInstance().sessionManager.endSession()
        }
    }

    private func sendCastMessage(_ message: CastSignalingMessage) throws {
        let json = String(data: try JSONEncoder().encode(message), encoding: .utf8) ?? "{}"
        var error: GCKError?
        guard signalingChannel.sendTextMessage(json, error: &error) else {
            throw error ?? CastError.castSessionFailed
        }
    }

    private func attachSignalingChannel(to castSession: GCKCastSession) {
        _ = castSession.add(signalingChannel)
    }

    private func publishDevices() {
        deviceContinuation?.yield(currentDevices())
    }

    private func currentDevices() -> [CastDevice] {
        let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
        var result: [CastDevice] = []
        for index in 0..<discoveryManager.deviceCount {
            let device = discoveryManager.device(at: index)
            devicesById[device.deviceID] = device
            result.append(
                CastDevice(
                    id: device.deviceID,
                    name: device.friendlyName ?? "Chromecast",
                    kind: .chromecast
                )
            )
        }
        return result
    }

    private func handleIncomingText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(CastSignalingMessage.self, from: data) else {
            return
        }
        if message.type == "pairing_code", let code = message.code {
            queue.sync { lastPairingCode = code }
        }
    }
}

extension CastSessionManager: GCKDiscoveryManagerListener {
    func didUpdateDeviceList() {
        publishDevices()
    }
}

extension CastSessionManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        guard let castSession = session as? GCKCastSession else { return }
        attachSignalingChannel(to: castSession)
        sessionStartContinuation?.resume()
        sessionStartContinuation = nil
    }

    func sessionManager(
        _ sessionManager: GCKSessionManager,
        didFailToStart session: GCKSession,
        withError error: Error
    ) {
        sessionStartContinuation?.resume(throwing: error)
        sessionStartContinuation = nil
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        if let castSession = session as? GCKCastSession {
            castSession.remove(signalingChannel)
        }
    }
}

extension CastSessionManager: GCKGenericChannelDelegate {
    func cast(
        _ channel: GCKGenericChannel,
        didReceiveTextMessage message: String,
        withNamespace protocolNamespace: String
    ) {
        handleIncomingText(message)
    }
}
