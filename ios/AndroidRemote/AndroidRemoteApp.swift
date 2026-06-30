import SwiftUI

@main
struct AndroidRemoteApp: App {
    init() {
        CastBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}
