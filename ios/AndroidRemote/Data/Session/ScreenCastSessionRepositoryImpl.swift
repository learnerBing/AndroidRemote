import Foundation

final class ScreenCastSessionRepositoryImpl: ScreenCastSessionRepository {
    func savePairedSession(_ session: PairingSession, device: CastDevice) {
        SessionStore.save(session: session, device: device)
    }

    func saveCastSession(sessionId: String, device: CastDevice, signalingHost: String) {
        SessionStore.saveCastSession(sessionId: sessionId, device: device, signalingHost: signalingHost)
    }

    func clearSession() {
        SessionStore.clear()
    }

    func loadSession() -> SessionStore.Snapshot? {
        SessionStore.load()
    }
}
