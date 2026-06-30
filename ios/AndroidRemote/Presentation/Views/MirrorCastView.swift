import SwiftUI

/// V1 mirror tab — routes between home, connecting, and streaming screens.
struct MirrorCastView: View {
    @StateObject private var viewModel = CastViewModel()

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            switch viewModel.connectionState {
            case .connecting:
                ConnectingView(viewModel: viewModel)
            case .streaming:
                MirrorStreamingView(viewModel: viewModel)
            default:
                MirrorHomeView(viewModel: viewModel)
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }
}

#Preview {
    MirrorCastView()
}
