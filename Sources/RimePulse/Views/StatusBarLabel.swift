import SwiftUI

struct StatusBarLabel: View {
    let stats: TypingStats?
    private let accentColor = Color.primary

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
            StatusMetricColumn(value: todayCharsText, symbol: "keyboard", color: accentColor)
            Rectangle()
                .fill(accentColor.opacity(0.35))
                .frame(width: 1, height: 14)
            StatusMetricColumn(value: currentSpeedText, symbol: "speedometer", color: accentColor)
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
    let color: Color
    private let columnWidth: CGFloat = 32
    private let valueHeight: CGFloat = 10
    private let iconHeight: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: columnWidth, height: valueHeight, alignment: .center)
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(color.opacity(0.9))
                .frame(width: columnWidth, height: iconHeight, alignment: .center)
        }
        .frame(width: columnWidth, height: valueHeight + iconHeight, alignment: .center)
    }
}
