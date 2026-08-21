import ReplayKit
import SwiftUI

struct BroadcastPickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        let hostBundle = Bundle.main.bundleIdentifier ?? "com.androidremote.app"
        picker.preferredExtension = "\(hostBundle).BroadcastExtension"
        picker.showsMicrophoneButton = false
        // Defaults to a black glyph with no background — invisible against this app's dark
        // (#0D1117) theme, and RPSystemBroadcastPickerView's own tint/icon rendering has proven
        // unreliable in practice (went invisible once before, in a961a53, from exactly this).
        // Callers now wrap this in a solid AppTheme.primary circle background for a guaranteed
        // visible tap target — so the icon itself needs to contrast against *that*, not the
        // app's dark background, hence white rather than AppTheme.primary here.
        picker.tintColor = .white
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
