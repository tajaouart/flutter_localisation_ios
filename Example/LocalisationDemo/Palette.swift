import SwiftUI

enum Palette {
    static let paper = Color(light: 0xF2F4F7, dark: 0x0F141C)
    static let surface = Color(light: 0xFFFFFF, dark: 0x171E29)
    static let ink = Color(light: 0x172033, dark: 0xE8ECF2)
    static let muted = Color(light: 0x5E6778, dark: 0x98A2B3)
    static let line = Color(light: 0xE1E5EC, dark: 0x263041)
    static let accent = Color(light: 0x0E7C66, dark: 0x3CC9A6)
    static let accentSoft = Color(light: 0xDDF1EB, dark: 0x173A33)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
