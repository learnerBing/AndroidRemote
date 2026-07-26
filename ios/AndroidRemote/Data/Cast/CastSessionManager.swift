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
        ARLog.info("Cast", "CastDeviceDiscovery.startBrowsing sdkAvailable=\(castSession.isCastSdkAvailable())")
        castSession.startDiscovery()
    }

    func stopBrowsing() {
        ARLog.info("Cast", "CastDeviceDiscovery.stopBrowsing")
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
        ARLog.info("Discovery", "CompositeDeviceDiscovery.startBrowsing")
        await castDiscovery.startBrowsing()
        await mdnsDiscovery.startBrowsing()

        Task {
            for await devices in castDiscovery.discoveredDevices {
                ARLog.info("Discovery", "cast devices update: \(devices.map(\.name))")
                castDevices = devices
                publish()
            }
        }
        Task {
            for await devices in mdnsDiscovery.discoveredDevices {
                ARLog.info("Discovery", "mDNS native devices update: \(devices.map(\.name))")
                nativeDevices = devices.map {
                    CastDevice(id: $0.id, name: $0.name, host: $0.host, port: $0.port, kind: .nativeTv)
                }
                publish()
            }
        }
    }

    func stopBrowsing() {
        ARLog.info("Discovery", "CompositeDeviceDiscovery.stopBrowsing")
        castDiscovery.stopBrowsing()
        mdnsDiscovery.stopBrowsing()
        continuation?.finish()
    }

    private func publish() {
        let combined = castDevices + nativeDevices
        ARLog.info("Discovery", "publishing \(combined.count) device(s): \(combined.map(\.name))")
        continuation?.yield(combined)
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
    private var diagnosticGeneration = 0

    private override init() {
        signalingChannel = GCKGenericChannel(namespace: CastConfig.customChannel)
        super.init()
        signalingChannel.delegate = self
    }

    var discoveredDevices: AsyncStream<[CastDevice]> {
        AsyncStream { continuation in
            self.deviceContinuation = continuation
            continuation.yield(self.onMain { self.currentDevices() })
        }
    }

    func latestPairingCode() -> String? {
        queue.sync { lastPairingCode }
    }

    func isCastSdkAvailable() -> Bool {
        CastConfig.isConfigured
    }

    func startDiscovery() {
        guard isCastSdkAvailable() else {
            ARLog.warn("Cast", "startDiscovery skipped — Cast SDK not configured")
            return
        }
        DispatchQueue.main.async {
            let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
            discoveryManager.add(self)
            discoveryManager.startDiscovery()
            ARLog.info("Cast", "discoveryManager.startDiscovery() called, current deviceCount=\(discoveryManager.deviceCount)")
            self.publishDevices()
            self.diagnosticGeneration += 1
            self.scheduleNoDeviceDiagnostic()
        }
    }

    func stopDiscovery() {
        guard isCastSdkAvailable() else { return }
        DispatchQueue.main.async {
            let discoveryManager = GCKCastContext.sharedInstance().discoveryManager
            discoveryManager.stopDiscovery()
            discoveryManager.remove(self)
            self.diagnosticGeneration += 1
            ARLog.info("Cast", "discoveryManager.stopDiscovery() called")
        }
    }

    /// No devices found shortly after starting discovery almost always means: iOS denied the
    /// "Local Network" permission prompt, the phone/TV are on different Wi‑Fi networks or subnets
    /// (guest network / band-steering / client isolation), or the receiver app is unpublished and
    /// this Cast device hasn't been added as an authorized test device in the Cast console.
    private func scheduleNoDeviceDiagnostic() {
        let generation = diagnosticGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.diagnosticGeneration == generation else { return }
            let count = GCKCastContext.sharedInstance().discoveryManager.deviceCount
            if count == 0 {
                ARLog.warn(
                    "Cast",
                    "no Cast devices found after 8s — check: (1) iOS Settings > AndroidRemote > Local Network is ON, "
                    + "(2) iPhone and TV are on the SAME Wi‑Fi network/band, "
                    + "(3) this Chromecast/Google TV is added as an authorized test device for the unpublished receiver app 02DE7020 in the Cast console."
                )
            }
        }
    }

    /// GCKCastContext APIs assert main-thread-only; the discovery call chain from
    /// `CastViewModel` passes through several non-`@MainActor` async types that can
    /// resume off the main thread, so reads/writes into the SDK must hop explicitly.
    private func onMain<T>(_ work: @escaping () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    func connect(to device: CastDevice) async throws {
        guard isCastSdkAvailable() else {
            ARLog.error("Cast", "connect(\(device.name)) failed — Cast SDK not configured")
            throw CastError.castSdkUnavailable
        }
        guard let gckDevice = devicesById[device.id] else {
            ARLog.error("Cast", "connect(\(device.name)) failed — device id \(device.id) not in devicesById (stale selection?)")
            throw CastError.castSessionFailed
        }
        queue.sync { lastPairingCode = nil }
        ARLog.info("Cast", "connect: starting session with \(device.name)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionStartContinuation = continuation
            DispatchQueue.main.async {
                let sessionManager = GCKCastContext.sharedInstance().sessionManager
                sessionManager.add(self)
                if !sessionManager.startSession(with: gckDevice) {
                    ARLog.error("Cast", "sessionManager.startSession(with:) returned false for \(device.name)")
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
        let devices = currentDevices()
        ARLog.info("Cast", "publishDevices: \(devices.count) device(s) — \(devices.map(\.name))")
        deviceContinuation?.yield(devices)
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
            ARLog.warn("Cast", "handleIncomingText: undecodable message \(text)")
            return
        }
        if message.type == "pairing_code", let code = message.code {
            ARLog.info("Cast", "received pairing_code from receiver")
            queue.sync { lastPairingCode = code }
        }
    }
}

extension CastSessionManager: GCKDiscoveryManagerListener {
    func didUpdateDeviceList() {
        ARLog.info("Cast", "didUpdateDeviceList fired")
        publishDevices()
    }
}

extension CastSessionManager: GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        guard let castSession = session as? GCKCastSession else { return }
        ARLog.info("Cast", "session didStart with \(session.device.friendlyName ?? "?")")
        attachSignalingChannel(to: castSession)
        sessionStartContinuation?.resume()
        sessionStartContinuation = nil
    }

    func sessionManager(
        _ sessionManager: GCKSessionManager,
        didFailToStart session: GCKSession,
        withError error: Error
    ) {
        ARLog.error("Cast", "session didFailToStart: \(error.localizedDescription)")
        sessionStartContinuation?.resume(throwing: error)
        sessionStartContinuation = nil
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        ARLog.info("Cast", "session didEnd" + (error.map { " error=\($0.localizedDescription)" } ?? ""))
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
