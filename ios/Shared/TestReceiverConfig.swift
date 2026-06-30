import Foundation

/// Default hosted test receiver (no Cast SDK required — open in any browser on TV/PC).
enum TestReceiverConfig {
    static let defaultReceiverBaseURL = "https://learnerbing.github.io/AndroidRemote/test-receiver.html"
    /// Main-app coordinator for pairing before broadcast (extension uses `CastConfig.signalingPort`).
    static let coordinatorPort: UInt16 = 8767
}

struct TestLinkResponse: Codable {
    let sessionId: String
    let signalingHost: String
    let signalingPort: Int
    let state: String
}
