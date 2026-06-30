import Foundation

protocol CastSessionManaging: AnyObject {
    var discoveredDevices: AsyncStream<[CastDevice]> { get }

    func startDiscovery()
    func stopDiscovery()
    func connect(to device: CastDevice) async throws
    func sendSessionPrepare(sessionId: String, host: String, port: Int) async throws
    func endSession()
    func isCastSdkAvailable() -> Bool
    func latestPairingCode() -> String?
}
