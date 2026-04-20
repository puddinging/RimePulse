import AppKit
import SwiftUI

enum MetricColors {
    // Digital palette — 沿用主题蓝 #00a5f7 的清爽调性
    static let sky     = Color(lightHex: "#0284c7", darkHex: "#00a5f7")  // 天蓝 — 速度 / 强调
    static let emerald = Color(lightHex: "#059669", darkHex: "#34d399")  // 翡翠 — 中文
    static let violet  = Color(lightHex: "#7c3aed", darkHex: "#a78bfa")  // 紫罗兰 — 英文
    static let rose    = Color(lightHex: "#db2777", darkHex: "#f472b6")  // 玫瑰粉 — 时长
    static let amber   = Color(lightHex: "#ca8a04", darkHex: "#facc15")  // 琥珀 — 提交

    static var totalChars: Color { .primary }
    static var charsCjk: Color { emerald }
    static var wordsEn: Color { violet }
    static var charsPerMinute: Color { sky }
    static var activeMinutes: Color { rose }
    static var commits: Color { amber }
}

extension Color {
    init(lightHex: String, darkHex: String) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let darkNames: [NSAppearance.Name] = [
                .darkAqua, .vibrantDark,
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastVibrantDark
            ]
            let isDark = darkNames.contains(appearance.name)
                || appearance.bestMatch(from: darkNames) != nil
            return NSColor(hex: isDark ? darkHex : lightHex)
        })
    }
}

private extension NSColor {
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xff) / 255
        let g = Double((v >>  8) & 0xff) / 255
        let b = Double( v        & 0xff) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
