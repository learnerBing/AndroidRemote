import SwiftUI

/// LAN test — Mac relay server + browser receiver (no Chromecast, no inbound iPhone TCP).
struct DirectTestView: View {
    @StateObject private var viewModel = DirectTestViewModel()

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            switch viewModel.connectionState {
            case .connecting:
                connectingView
            case .streaming:
                streamingView
            default:
                setupView
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .alert("Test Mode Error", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                stepCard(number: 1, title: "Start Mac relay server") {
                    Text("On your Mac (same Wi‑Fi):")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text("python3 tools/lan-test-server.py")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.primary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text("Note the Mac IP printed by the script (not 0.0.0.0).")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 4)
                }

                stepCard(number: 2, title: "Open receiver in browser FIRST") {
                    Text("Must be open before Link Receiver on iPhone:")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    Text(viewModel.receiverPageURL)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.primary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                stepCard(number: 3, title: "Mac relay host (from script output)") {
                    TextField("192.168.x.x", text: $viewModel.relayHost)
                        .keyboardType(.decimalPad)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    TextField("Port", text: $viewModel.relayPort)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .background(AppTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let code = viewModel.detectedCode {
                    Text("Linked to browser code: \(code)")
                        .font(.caption.monospaced())
                        .foregroundStyle(AppTheme.success)
                }

                Button(action: viewModel.linkReceiver) {
                    Text("Link Receiver")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .disabled(!viewModel.canLink)
                .opacity(viewModel.canLink ? 1 : 0.5)

                Text("No pairing code needed — auto-detects open browser page.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().tint(AppTheme.primary).scaleEffect(1.2)
            Text("Receiver linked")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Start screen broadcast to begin mirroring")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Text("The browser shows 204 until you start broadcast — that is normal.")
                .font(.caption)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            Text("Link Receiver must succeed before broadcast.")
                .font(.caption)
                .foregroundStyle(.orange)
            BroadcastPickerRepresentable()
                .frame(width: 52, height: 52)
            Spacer()
            Button("Cancel") { viewModel.cancelConnecting() }
                .foregroundStyle(AppTheme.primary)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
    }

    private var streamingView: some View {
        VStack(spacing: 32) {
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(AppTheme.success).frame(width: 8, height: 8)
                Text("Live (test mode)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
            }
            Text("Mirroring to web receiver")
                .font(.title3.bold())
            BroadcastPickerRepresentable().frame(width: 52, height: 52)
            Spacer()
            Button("Stop") { viewModel.resetSession() }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.bottom, 32)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Direct LAN Test", systemImage: "antenna.radiowaves.left.and.right")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Mac relay handles signaling. No Chromecast or iPhone inbound ports.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func stepCard<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.background)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.primary)
                    .clipShape(Circle())
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
            }
            content()
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
    }
}

#Preview {
    DirectTestView()
}
