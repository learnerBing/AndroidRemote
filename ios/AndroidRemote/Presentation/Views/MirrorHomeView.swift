import SwiftUI

/// Stitch V1 home — TV discovery, pairing code, Start Casting.
struct MirrorHomeView: View {
    @ObservedObject var viewModel: CastViewModel
    @FocusState private var codeFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                deviceList
                pairingSection
                broadcastFooter
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .alert("Connection Failed", isPresented: $viewModel.showError) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            Text(viewModel.errorMessage ?? "Could not connect to the TV.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(AppTheme.primary)
                .symbolRenderingMode(.hierarchical)

            Text("AndroidRemote")
                .font(.title.bold())
                .foregroundStyle(AppTheme.textPrimary)

            Text("Cast iPhone to Google TV")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            if !viewModel.castSdkReady {
                Text("Set Cast App ID in CastConfig.swift")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Devices")
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)

            if viewModel.devices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(AppTheme.primary)
                    Text("Looking for Chromecast & Google TV…")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            } else {
                ForEach(viewModel.devices) { device in
                    deviceRow(device)
                }
            }
        }
    }

    private func deviceRow(_ device: CastDevice) -> some View {
        let isSelected = viewModel.selectedDevice?.id == device.id

        return Button {
            viewModel.selectDevice(device)
            codeFieldFocused = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tv.fill")
                    .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.textSecondary)

                Text(device.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .padding(16)
            .background(AppTheme.surface)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .stroke(AppTheme.primary, lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var pairingSection: some View {
        if viewModel.selectedDevice != nil {
            VStack(spacing: 16) {
                if viewModel.selectedDevice?.isChromecast == true {
                    Text(viewModel.receivedTvCode != nil
                         ? "Code from TV: \(viewModel.receivedTvCode!)"
                         : "Connect to TV first — code will appear on TV and here")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    PairingCodeField(code: $viewModel.pairingCode)
                        .focused($codeFieldFocused)
                }

                Button(action: viewModel.startCast) {
                    Text(viewModel.selectedDevice?.isChromecast == true ? "Connect to TV" : "Start Casting")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .disabled(!viewModel.canStartCasting)
                .opacity(viewModel.canStartCasting ? 1 : 0.5)
            }
        }
    }

    private var broadcastFooter: some View {
        VStack(spacing: 10) {
            Text("Then start screen broadcast")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            BroadcastPickerRepresentable()
                .frame(width: 52, height: 52)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

/// Six-digit code entry styled for Stitch home screen.
private struct PairingCodeField: View {
    @Binding var code: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Enter code from your TV")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            TextField("", text: $code, prompt: Text("000000").foregroundStyle(AppTheme.textSecondary.opacity(0.4)))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(6))
                    if filtered != newValue { code = filtered }
                }
        }
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        MirrorHomeView(viewModel: CastViewModel())
    }
}
