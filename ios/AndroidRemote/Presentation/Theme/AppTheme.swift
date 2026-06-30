import SwiftUI

/// Design tokens from Stitch V1 (docs/STITCH_DESIGNS.md).
enum AppTheme {
    static let background = Color(hex: 0x0D1117)
    static let surface = Color(hex: 0x161B22)
    static let primary = Color(hex: 0x58A6FF)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x8B949E)
    static let success = Color(hex: 0x3FB950)
    static let cornerRadius: CGFloat = 12
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
