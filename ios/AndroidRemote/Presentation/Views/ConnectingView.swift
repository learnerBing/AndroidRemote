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

            ProgressView()
                .tint(AppTheme.primary)
                .scaleEffect(1.1)
                .padding(.top, 24)

            if viewModel.pairedTVName != nil {
                VStack(spacing: 10) {
                    Text("Then start screen broadcast")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 24)

                    BroadcastPickerRepresentable()
                        .frame(width: 52, height: 52)
                }
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
            return "Establishing secure connection…"
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
