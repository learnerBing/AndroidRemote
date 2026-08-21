import ReplayKit
import SwiftUI

struct BroadcastPickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        let hostBundle = Bundle.main.bundleIdentifier ?? "com.androidremote.app"
        picker.preferredExtension = "\(hostBundle).BroadcastExtension"
        picker.showsMicrophoneButton = false
        // Defaults to a black glyph with no background — invisible against this app's dark
        // (#0D1117) theme. Tint it to match AppTheme.primary so it's actually visible.
        picker.tintColor = UIColor(red: 0x58 / 255, green: 0xA6 / 255, blue: 0xFF / 255, alpha: 1)
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
