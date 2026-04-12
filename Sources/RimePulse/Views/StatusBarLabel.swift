import SwiftUI

struct StatusBarLabel: View {
    let stats: TypingStats?

    private var todayCharsText: String {
        guard let s = stats, s.chars > 0 else { return "0" }
        return compactNumber(s.chars)
    }

    private var currentSpeedText: String {
        guard let s = stats, s.chars > 0 else { return "0" }
        return "\(s.liveCurrentCpm)"
    }

    var body: some View {
        HStack(spacing: 7) {
            StatusMetricColumn(value: todayCharsText, symbol: "keyboard")
            Rectangle()
                .fill(.secondary.opacity(0.35))
                .frame(width: 1, height: 14)
            StatusMetricColumn(value: currentSpeedText, symbol: "bolt.fill")
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .fixedSize()
        .monospacedDigit()
    }
}

private struct StatusMetricColumn: View {
    let value: String
    let symbol: String

    var body: some View {
        VStack(spacing: -1) {
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
