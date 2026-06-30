import SwiftUI

/// Active mirroring state — live indicator + broadcast controls.
struct MirrorStreamingView: View {
    @ObservedObject var viewModel: CastViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(AppTheme.surface)
                    .frame(width: 120, height: 120)

                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.primary)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(AppTheme.success)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                }

                Text("Mirroring to \(viewModel.pairedTVName ?? "TV")")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your screen is being cast over the local network.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 12) {
                Text("Restart broadcast")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)

                BroadcastPickerRepresentable()
                    .frame(width: 52, height: 52)

                Button("Stop Casting") {
                    viewModel.resetSession()
                }
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .padding(.top, 8)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        MirrorStreamingView(viewModel: CastViewModel())
    }
}
