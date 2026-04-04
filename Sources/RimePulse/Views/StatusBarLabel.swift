import SwiftUI

struct StatusBarLabel: View {
    let stats: TypingStats?

    private var formatted: String {
        guard let s = stats, s.chars > 0 else {
            return String(format: "\u{1F4CA}%5d字 \u{26A1}%3d/分 \u{1F525}%3d", 0, 0, 0)
        }
        return String(format: "\u{1F4CA}%5d字 \u{26A1}%3d/分 \u{1F525}%3d",
                       s.chars, s.charsPerMinute, s.peakCpm)
    }

    var body: some View {
        Text(formatted)
            .font(.system(size: 12, design: .monospaced))
    }
}
