import Foundation
import GoogleCast

/// Bootstraps Google Cast SDK (main app only).
enum CastBootstrap {
    static func configure() {
        guard CastConfig.isConfigured else {
            ARLog.warn("Cast", "CastBootstrap.configure skipped — receiverAppId is still the placeholder")
            return
        }
        ARLog.info("Cast", "CastBootstrap.configure appId=\(CastConfig.receiverAppId)")
        let criteria = GCKDiscoveryCriteria(applicationID: CastConfig.receiverAppId)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        // App drives discovery itself (no GCKUICastButton), so start it immediately rather than
        // waiting for a cast-button tap that never happens.
        options.startDiscoveryAfterFirstTapOnCastButton = false
        // Defaults to YES, which suspends the Cast session — and fires SENDER_DISCONNECTED on
        // the receiver — the instant the user backgrounds the main app. That's exactly what
        // happens when screen mirroring is working as intended: the Broadcast Extension keeps
        // running and streaming independently of the main app's lifecycle (see CLAUDE.md), so
        // backgrounding to use another app mid-mirror is completely normal, not a teardown signal.
        options.suspendSessionsWhenBackgrounded = false
        GCKCastContext.setSharedInstanceWith(options)
        let filter = GCKLoggerFilter()
        filter.minimumLevel = .verbose
        GCKLogger.sharedInstance().filter = filter
        GCKLogger.sharedInstance().delegate = CastSdkLogRelay.shared
        ARLog.info("Cast", "GCKCastContext configured")
    }
}

/// Relays the Cast SDK's internal logging (discovery/session-manager internals not otherwise
/// visible) into our own log stream, per Google's documented debugging setup.
final class CastSdkLogRelay: NSObject, GCKLoggerDelegate {
    static let shared = CastSdkLogRelay()

    func logMessage(_ message: String, at level: GCKLoggerLevel, fromFunction function: String, location: String) {
        ARLog.info("CastSDK", "\(function): \(message)")
    }
}
