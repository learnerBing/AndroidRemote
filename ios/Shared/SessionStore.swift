import Foundation

/// Persists cast session between main app and Broadcast Upload Extension via App Group.
enum SessionStore {
    static let appGroupId = "group.com.androidremote.shared"

    private enum Key {
        static let sessionId = "cast.sessionId"
        static let signalingHost = "cast.signalingHost"
        static let signalingPort = "cast.signalingPort"
        static let deviceName = "cast.deviceName"
        static let transport = "cast.transport"
        static let isPaired = "cast.isPaired"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    struct Snapshot: Equatable, Codable {
        let sessionId: String
        let transport: SignalingTransport
        let signalingHost: String
        let signalingPort: Int
        let deviceName: String

        var tvHost: String { signalingHost }
        var tvPort: Int { signalingPort }
        var tvName: String { deviceName }
    }

    private static let snapshotFileName = "active-session.json"

    private static func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    private static func writeSnapshotFile(_ snapshot: Snapshot) {
        guard let url = appGroupContainerURL()?.appendingPathComponent(snapshotFileName) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func readSnapshotFile() -> Snapshot? {
        guard let url = appGroupContainerURL()?.appendingPathComponent(snapshotFileName),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static func removeSnapshotFile() {
        guard let url = appGroupContainerURL()?.appendingPathComponent(snapshotFileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func persist(_ snapshot: Snapshot) {
        writeSnapshotFile(snapshot)
    }

    static func saveDirectTestSession(
        sessionId: String,
        device: CastDevice,
        relayHost: String,
        relayPort: Int
    ) {
        guard let defaults else { return }
        defaults.set(sessionId, forKey: Key.sessionId)
        defaults.set(relayHost, forKey: Key.signalingHost)
        defaults.set(relayPort, forKey: Key.signalingPort)
        defaults.set(device.name, forKey: Key.deviceName)
        defaults.set(SignalingTransport.directLanRelay.rawValue, forKey: Key.transport)
        defaults.set(true, forKey: Key.isPaired)
        defaults.synchronize()
        persist(Snapshot(
            sessionId: sessionId,
            transport: .directLanRelay,
            signalingHost: relayHost,
            signalingPort: relayPort,
            deviceName: device.name
        ))
    }

    static func saveCastSession(
        sessionId: String,
        device: CastDevice,
        signalingHost: String,
        signalingPort: Int = CastConfig.signalingPort
    ) {
        guard let defaults else { return }
        defaults.set(sessionId, forKey: Key.sessionId)
        defaults.set(signalingHost, forKey: Key.signalingHost)
        defaults.set(signalingPort, forKey: Key.signalingPort)
        defaults.set(device.name, forKey: Key.deviceName)
        defaults.set(SignalingTransport.castReceiver.rawValue, forKey: Key.transport)
        defaults.set(true, forKey: Key.isPaired)
    }

    static func save(session: PairingSession, device: CastDevice) {
        guard let defaults else { return }
        defaults.set(session.sessionId, forKey: Key.sessionId)
        defaults.set(device.host, forKey: Key.signalingHost)
        defaults.set(device.port, forKey: Key.signalingPort)
        defaults.set(device.name, forKey: Key.deviceName)
        defaults.set(SignalingTransport.nativeTv.rawValue, forKey: Key.transport)
        defaults.set(true, forKey: Key.isPaired)
    }

    static func load() -> Snapshot? {
        if let fromFile = readSnapshotFile() { return fromFile }
        guard let defaults,
              defaults.bool(forKey: Key.isPaired),
              let sessionId = defaults.string(forKey: Key.sessionId),
              let host = defaults.string(forKey: Key.signalingHost),
              let name = defaults.string(forKey: Key.deviceName),
              let transportRaw = defaults.string(forKey: Key.transport),
              let transport = SignalingTransport(rawValue: transportRaw) else {
            return nil
        }
        let port = defaults.integer(forKey: Key.signalingPort)
        guard port > 0 else { return nil }
        return Snapshot(
            sessionId: sessionId,
            transport: transport,
            signalingHost: host,
            signalingPort: port,
            deviceName: name
        )
    }

    static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: Key.sessionId)
        defaults.removeObject(forKey: Key.signalingHost)
        defaults.removeObject(forKey: Key.signalingPort)
        defaults.removeObject(forKey: Key.deviceName)
        defaults.removeObject(forKey: Key.transport)
        defaults.set(false, forKey: Key.isPaired)
        defaults.synchronize()
        removeSnapshotFile()
    }
}
