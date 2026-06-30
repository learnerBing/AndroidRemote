import SwiftUI

@main
struct AndroidRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            DirectTestView()
                .preferredColorScheme(.dark)
        }
    }
}
