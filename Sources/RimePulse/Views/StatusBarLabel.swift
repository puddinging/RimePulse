import SwiftUI

struct StatusBarLabel: View {
    let stats: TypingStats?

    static func format(stats: TypingStats?) -> String {
        guard let s = stats, s.chars > 0 else {
            return "0 chars | 0 cpm | peak 0"
        }
        return "\(s.chars) chars | \(s.charsPerMinute) cpm | peak \(s.peakCpm)"
    }

    var body: some View {
        Text(Self.format(stats: stats))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .monospacedDigit()
    }
}
