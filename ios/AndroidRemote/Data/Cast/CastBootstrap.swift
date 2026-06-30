import Foundation
import GoogleCast

/// Bootstraps Google Cast SDK (main app only).
enum CastBootstrap {
    static func configure() {
        guard CastConfig.receiverAppId != "YOUR_CAST_APP_ID" else { return }
        let criteria = GCKDiscoveryCriteria(applicationID: CastConfig.receiverAppId)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
    }
}
