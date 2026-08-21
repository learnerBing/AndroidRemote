import SwiftUI

/// Stitch V1 connecting state — shown after Start Casting until stream is live.
struct ConnectingView: View {
    @ObservedObject var viewModel: CastViewModel
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Cancel") { viewModel.cancelConnecting() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(AppTheme.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()

            connectionGraphic
                .padding(.bottom, 40)

            Text(statusMessage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Pairing itself is genuinely automatic — a spinner is honest there. Once paired,
            // nothing happens until the user taps the broadcast picker below; showing a spinner
            // here as well falsely implied the app was still working on its own, so people just
            // sat and waited for a connection that needed their tap to even start.
            if viewModel.pairedTVName == nil {
                ProgressView()
                    .tint(AppTheme.primary)
                    .scaleEffect(1.1)
                    .padding(.top, 24)
            } else {
                VStack(spacing: 14) {
                    // A colored, filled circle — not just a tinted icon glyph. RPSystemBroadcastPickerView's
                    // own tint/icon rendering has proven unreliable in practice (this button has
                    // gone invisible before, in a961a53, from exactly that fragility); a solid
                    // background makes the tap target visible regardless of icon rendering.
                    BroadcastPickerRepresentable()
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(AppTheme.primary))
                        .clipShape(Circle())
                        .shadow(color: AppTheme.primary.opacity(0.4), radius: 12, y: 4)

                    Text("Tap to start casting")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .padding(.top, 24)
            }

            Spacer()

            Text("Keep your devices close and on the same Wi‑Fi network.")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
        }
    }

    private var statusMessage: String {
        if viewModel.pairedTVName != nil {
            return "Ready to cast — tap the button below"
        }
        return "Pairing with TV…"
    }

    private var connectionGraphic: some View {
        HStack(spacing: 32) {
            deviceIcon(systemName: "iphone", label: "iPhone")

            ZStack {
                Circle()
                    .stroke(AppTheme.primary.opacity(0.2), lineWidth: 2)
                    .frame(width: pulse ? 72 : 56, height: pulse ? 72 : 56)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                Image(systemName: "link")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
            }

            deviceIcon(systemName: "tv", label: viewModel.selectedDevice?.name ?? "TV")
        }
        .onAppear { pulse = true }
    }

    private func deviceIcon(systemName: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 36))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 72, height: 72)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 88)
        }
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        ConnectingView(viewModel: CastViewModel())
    }
}
