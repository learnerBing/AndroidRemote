import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: CastMode = .screen

    var body: some View {
        TabView(selection: $selectedTab) {
            MirrorCastView()
                .tabItem {
                    Label(CastMode.screen.displayName, systemImage: CastMode.screen.systemImage)
                }
                .tag(CastMode.screen)

            ComingSoonTabView(mode: .photo)
                .tabItem {
                    Label(CastMode.photo.displayName, systemImage: CastMode.photo.systemImage)
                }
                .tag(CastMode.photo)

            ComingSoonTabView(mode: .video)
                .tabItem {
                    Label(CastMode.video.displayName, systemImage: CastMode.video.systemImage)
                }
                .tag(CastMode.video)

            ComingSoonTabView(mode: .iptv)
                .tabItem {
                    Label(CastMode.iptv.displayName, systemImage: CastMode.iptv.systemImage)
                }
                .tag(CastMode.iptv)

            ComingSoonTabView(mode: .youtube)
                .tabItem {
                    Label(CastMode.youtube.displayName, systemImage: CastMode.youtube.systemImage)
                }
                .tag(CastMode.youtube)

            ComingSoonTabView(mode: .remote)
                .tabItem {
                    Label(CastMode.remote.displayName, systemImage: CastMode.remote.systemImage)
                }
                .tag(CastMode.remote)
        }
        .tint(AppTheme.primary)
    }
}

struct ComingSoonTabView: View {
    let mode: CastMode

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 56))
                    .foregroundStyle(AppTheme.primary.opacity(0.5))

                Text(mode.displayName)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Coming in V2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary.opacity(0.15))
                    .clipShape(Capsule())

                Text(v2Description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var v2Description: String {
        switch mode {
        case .screen: return ""
        case .photo: return "Cast photos from your library to the TV slideshow viewer."
        case .video: return "Play videos from your iPhone on the big screen."
        case .iptv: return "Stream live TV channels from your M3U playlists."
        case .youtube: return "Send YouTube links to open on your Android TV."
        case .remote: return "Control your TV with a virtual remote from your iPhone."
        }
    }
}

#Preview {
    MainTabView()
}
