import SwiftUI

@main
struct AndroidRemoteApp: App {
    init() {
        CastBootstrap.configure()
        LocalNetworkAuthorization.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}
