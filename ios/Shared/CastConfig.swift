import Foundation

/// Google Cast custom receiver configuration (Cast-first V1 path).
enum CastConfig {
    /// Register `cast-receiver/index.html` in the [Cast SDK Developer Console](https://cast.google.com/publish).
    /// Replace with your App ID before shipping.
    static let receiverAppId = "YOUR_CAST_APP_ID"

    static let customChannel = "urn:x-cast:com.androidremote.signaling"
    static let signalingPort = 8766
}
