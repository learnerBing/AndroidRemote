import Foundation

// MARK: - ARCP JSON models (shared: main app + broadcast extension)

struct ARCPPairRequest: Encodable {
    let code: String
}

struct ARCPPairResponse: Decodable {
    let sessionId: String
}

struct ARCPSdpMessage: Codable {
    let sessionId: String
    let type: String
    let sdp: String
}

struct ARCPIceMessage: Codable {
    let sessionId: String
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

struct ARCPIceCandidateDto: Codable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

struct ARCPIceListResponse: Codable {
    let candidates: [ARCPIceCandidateDto]
}

struct ARCPStatusResponse: Codable {
    let state: String
}

struct ARCPHealthResponse: Codable {
    let ok: Bool
}

struct IceCandidate: Equatable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32
}

enum CastError: LocalizedError {
    case answerTimeout
    case invalidPairingCode
    case discoveryFailed
    case relayBrowserNotOpen
    case notConfigured
    case webRtcUnavailable
    case castSdkUnavailable
    case castSessionFailed
    case lanAddressUnavailable

    var errorDescription: String? {
        switch self {
        case .answerTimeout: return "TV did not respond in time"
        case .invalidPairingCode: return "Invalid pairing code"
        case .discoveryFailed: return "Could not reach Mac relay — same Wi‑Fi, IP 192.168.18.6, port 8080, allow Local Network"
        case .relayBrowserNotOpen: return "Open test-receiver.html in your Mac browser first, then tap Link Receiver"
        case .notConfigured: return "Session not configured — Link Receiver on Test tab before broadcast"
        case .webRtcUnavailable: return "WebRTC SDK not linked — add GoogleWebRTC via SPM"
        case .castSdkUnavailable: return "Google Cast SDK not linked — resolve SPM packages in Xcode"
        case .castSessionFailed: return "Could not start Cast session"
        case .lanAddressUnavailable: return "Could not determine iPhone Wi‑Fi address"
        }
    }
}

// MARK: - Cast custom messages (main app ↔ web receiver)

struct CastSignalingMessage: Codable {
    let type: String
    let sessionId: String?
    let code: String?
    let signalingHost: String?
    let signalingPort: Int?
    let state: String?

    static func pairingCode(_ code: String) -> CastSignalingMessage {
        CastSignalingMessage(type: "pairing_code", sessionId: nil, code: code, signalingHost: nil, signalingPort: nil, state: nil)
    }

    static func sessionPrepare(sessionId: String, host: String, port: Int) -> CastSignalingMessage {
        CastSignalingMessage(type: "session_prepare", sessionId: sessionId, code: nil, signalingHost: host, signalingPort: port, state: nil)
    }

    static func status(_ state: String) -> CastSignalingMessage {
        CastSignalingMessage(type: "status", sessionId: nil, code: nil, signalingHost: nil, signalingPort: nil, state: state)
    }
}
