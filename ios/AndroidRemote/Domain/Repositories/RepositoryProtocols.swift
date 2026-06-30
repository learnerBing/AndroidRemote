import Foundation

// MARK: - Repository Protocols

protocol DeviceDiscoveryRepository {
    func startBrowsing() async
    func stopBrowsing()
    var discoveredDevices: AsyncStream<[CastDevice]> { get }
}

protocol SignalingClientRepository {
    func bind(device: CastDevice)
    func pair(code: String) async throws -> PairingSession
    func pollStatus(sessionId: String) async throws -> String
}

protocol ScreenCastSessionRepository {
    func savePairedSession(_ session: PairingSession, device: CastDevice)
    func saveCastSession(sessionId: String, device: CastDevice, signalingHost: String)
    func clearSession()
    func loadSession() -> SessionStore.Snapshot?
}
