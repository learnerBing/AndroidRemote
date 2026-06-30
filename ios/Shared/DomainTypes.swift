import Foundation

enum ReceiverKind: String, Codable, Equatable {
    /// Chromecast / Google TV — custom web receiver (no TV app install).
    case chromecast
    /// Optional native Android TV app with on-device HTTP signaling.
    case nativeTv
}

struct CastDevice: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let kind: ReceiverKind

    init(id: String, name: String, host: String = "", port: Int = 0, kind: ReceiverKind = .chromecast) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.kind = kind
    }

    var isChromecast: Bool { kind == .chromecast }
}

struct PairingSession: Equatable, Codable {
    let sessionId: String
    let pairingCode: String
    let expiresAt: Date
}

enum StreamCodec: String, Codable {
    case h264
}

enum ScreenVideoLayout: Equatable {
    case portrait
    case landscape
}

struct StreamConfig: Equatable {
    var width: Int = 1280
    var height: Int = 720
    var fps: Int = 30
    var maxBitrateKbps: Int = 2500
    var minBitrateKbps: Int = 800
    var codec: StreamCodec = .h264

    /// Chromecast / extension memory-safe default.
    static let castReceiver = StreamConfig()

    /// Direct Mac LAN relay — same Wi‑Fi, higher resolution and bitrate.
    static let lanRelay = StreamConfig(
        width: 1920,
        height: 1080,
        fps: 30,
        maxBitrateKbps: 8000,
        minBitrateKbps: 2500
    )

    /// `width`×`height` is the landscape box; portrait swaps the long and short edges.
    func outputDimensions(for layout: ScreenVideoLayout) -> (width: Int, height: Int) {
        let longEdge = max(width, height)
        let shortEdge = min(width, height)
        switch layout {
        case .portrait:
            return (shortEdge, longEdge)
        case .landscape:
            return (longEdge, shortEdge)
        }
    }
}

enum ConnectionState: Equatable {
    case idle
    case discovering
    case pairing
    case connecting
    case streaming
    case disconnected
    case error(String)
}
