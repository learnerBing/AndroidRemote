import Foundation

final class ScreenCastSessionRepositoryImpl: ScreenCastSessionRepository {
    func savePairedSession(_ session: PairingSession, device: CastDevice) {
        SessionStore.save(session: session, device: device)
    }

    func saveCastSession(sessionId: String, device: CastDevice, signalingHost: String) {
        SessionStore.saveCastSession(sessionId: sessionId, device: device, signalingHost: signalingHost)
    }

    func saveDirectTestSession(sessionId: String, device: CastDevice, relayHost: String, relayPort: Int) {
        SessionStore.saveDirectTestSession(
            sessionId: sessionId,
            device: device,
            relayHost: relayHost,
            relayPort: relayPort
        )
    }

    func clearSession() {
        SessionStore.clear()
    }

    func loadSession() -> SessionStore.Snapshot? {
        SessionStore.load()
    }
}
