import SwiftUI

/// App entry — Cast tab (Chromecast / Google TV) alongside the LAN relay test tab.
struct MainTabView: View {
    var body: some View {
        TabView {
            MirrorCastView()
                .tabItem { Label("Cast", systemImage: "tv") }

            DirectTestView()
                .tabItem { Label("LAN Test", systemImage: "wifi") }
        }
        .tint(AppTheme.primary)
    }
}

#Preview {
    MainTabView()
}
