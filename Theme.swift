import SwiftUI

struct Theme {
    static let background = Color(hex: "000000")
    static let surface = Color(hex: "0A0D0D")
    static let surface2 = Color(hex: "101615")
    static let border = Color(hex: "16302E")
    static let aqua = Color(hex: "17E6C8")
    static let aquaDim = Color(hex: "0C8C7A")
    static let aquaDeep = Color(hex: "063B38")
    static let textHi = Color(hex: "E8FBF8")
    static let textMid = Color(hex: "7FB8B0")
    static let textLow = Color(hex: "4A6A65")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
