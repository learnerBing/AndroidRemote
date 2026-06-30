import SwiftUI

/// LAN test path — connect to `test-receiver.html` without Chromecast registration.
struct DirectTestView: View {
    @StateObject private var viewModel = DirectTestViewModel()
    @FocusState private var codeFieldFocused: Bool

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

                stepCard(number: 1, title: "Open receiver on TV or laptop") {
                    Text("Open this URL in a browser on the same Wi‑Fi:")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text(viewModel.receiverURLWithIP)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.primary)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                }

                stepCard(number: 2, title: "Copy code from receiver page") {
                    Text("The web page shows a 6-digit code. Enter it here:")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    TextField("000000", text: $viewModel.pairingCode)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 32, weight: .semibold, design: .monospaced))
                        .padding(.vertical, 16)
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                        .focused($codeFieldFocused)
                        .onChange(of: viewModel.pairingCode) { _, newValue in
                            let filtered = String(newValue.filter(\.isNumber).prefix(6))
                            if filtered != newValue { viewModel.pairingCode = filtered }
                        }
                }

                networkInfo

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

                Text("No Chromecast or Cast device registration required.")
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

            ProgressView()
                .tint(AppTheme.primary)
                .scaleEffect(1.2)

            Text("Receiver linked")
                .font(.title3.bold())
                .foregroundStyle(AppTheme.textPrimary)

            Text("Start screen broadcast to begin mirroring")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

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
                .foregroundStyle(AppTheme.textPrimary)

            BroadcastPickerRepresentable()
                .frame(width: 52, height: 52)

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

            Text("Bypass Chromecast — pair with the browser receiver over Wi‑Fi.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var networkInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("iPhone IP")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Button("Refresh") { viewModel.refreshNetworkInfo() }
                    .font(.caption.weight(.medium))
            }

            Text(viewModel.iphoneIP)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(AppTheme.primary)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.coordinatorRunning ? AppTheme.success : .orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.coordinatorRunning
                     ? "Pairing server running (port \(TestReceiverConfig.coordinatorPort))"
                     : "Pairing server not running")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
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
