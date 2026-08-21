import Foundation

/// Google Cast custom receiver configuration (Cast-first V1 path).
enum CastConfig {
    /// Registered in the [Cast SDK Developer Console](https://cast.google.com/publish) as "AndroidReceiver"
    /// (Custom Receiver, unpublished — launches only on devices authorized in that console).
    /// Receiver Application URL: https://learnerbing.github.io/AndroidRemote/
    static let receiverAppId = "02DE7020"

    static let customChannel = "urn:x-cast:com.androidremote.signaling"
    static let signalingPort = 8766

    /// False when `receiverAppId` is still the unconfigured placeholder.
    static var isConfigured: Bool {
        receiverAppId != "YOUR_CAST_APP_ID"
    }
}
