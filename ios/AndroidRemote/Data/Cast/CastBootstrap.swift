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
        GCKCastContext.setSharedInstanceWith(options)
        ARLog.info("Cast", "GCKCastContext configured")
    }
}
