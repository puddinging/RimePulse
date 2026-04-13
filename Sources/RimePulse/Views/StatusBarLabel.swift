import SwiftUI

struct StatusBarLabel: View {
    let stats: TypingStats?

    static func menuText(stats: TypingStats?) -> String {
        guard let s = stats, s.chars > 0 else { return "0 | 0" }
        return "\(compactNumber(s.chars)) | \(s.liveCurrentCpm)"
    }

    var body: some View {
        Text(Self.menuText(stats: stats))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .monospacedDigit()
    }
}
