import ReplayKit
import SwiftUI

struct BroadcastPickerRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 52, height: 52))
        let hostBundle = Bundle.main.bundleIdentifier ?? "com.androidremote.app"
        picker.preferredExtension = "\(hostBundle).BroadcastExtension"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
