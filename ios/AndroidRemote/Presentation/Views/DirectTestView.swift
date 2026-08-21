import SwiftUI

/// Screen recording to Mac relay — link browser receiver, then start broadcast.
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
                    Text("Hard refresh after each Link Receiver on iPhone:")
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
            if viewModel.linkedSessionId == nil {
                Text("No linked session — tap Link Receiver and wait for the green code.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Session ready — start broadcast below.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.success)
            }
            Text("Use the in-app button (not Control Center). Video only on this branch — no mic/audio track.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            BroadcastPickerRepresentable()
                .frame(width: 52, height: 52)
                .opacity(viewModel.linkedSessionId == nil ? 0.4 : 1)
                .disabled(viewModel.linkedSessionId == nil)
            if viewModel.broadcastActive {
                Text("Broadcast started — keep this screen open until Live appears.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.success)
                    .multilineTextAlignment(.center)
            } else if viewModel.relayStatus == "broadcasting" {
                Text("Extension is starting WebRTC…")
                    .font(.caption)
                    .foregroundStyle(AppTheme.success)
                    .multilineTextAlignment(.center)
            } else if viewModel.relayStatus == "connecting" {
                Text("Negotiating with browser — video should appear soon.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.success)
                    .multilineTextAlignment(.center)
            }
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
                Text("Live")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.success)
            }
            Text("Recording to Mac browser")
                .font(.title3.bold())
            if viewModel.broadcastActive {
                Text("Broadcast running — waiting for video…")
                    .font(.caption)
                    .foregroundStyle(AppTheme.success)
            }
            BroadcastPickerRepresentable().frame(width: 52, height: 52)
            Spacer()
            Button("Stop") { viewModel.resetSession() }
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.bottom, 32)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Screen to Mac", systemImage: "display.and.arrow.down")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
            Text("Record your iPhone screen and audio on a Mac browser over Wi‑Fi.")
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
