import Foundation

/// Where ARCP HTTP signaling runs for the active session.
enum SignalingTransport: String, Codable, Equatable {
    /// iPhone Broadcast Extension hosts signaling; Cast web receiver connects over LAN.
    case castReceiver
    /// Mac/PC LAN relay hosts signaling (Test tab — iPhone outbound only).
    case directLanRelay
    /// Native Android TV app hosts signaling on the TV.
    case nativeTv
}
