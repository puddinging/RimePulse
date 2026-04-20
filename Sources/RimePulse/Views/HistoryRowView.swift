import SwiftUI

struct HistoryRowView: View {
    let stats: TypingStats

    private var shortDate: String {
        let parts = stats.date.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])-\(parts[2])"
        }
        return stats.date
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(shortDate)
                .frame(width: 36, alignment: .leading)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            numberCell(
                compactNumber(stats.chars),
                unit: "字",
                width: 52,
                color: MetricColors.totalChars
            )
            numberCell(
                compactNumber(stats.charsPerMinute),
                unit: "/分",
                width: 50,
                color: MetricColors.charsPerMinute
            )
            numberCell(
                compactNumber(stats.commits),
                unit: "次",
                width: 44,
                color: MetricColors.commits
            )
            numberCell(
                String(format: "%.0f", stats.activeMinutes),
                unit: "分",
                width: 32,
                color: MetricColors.activeMinutes
            )
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
    }

    private func numberCell(_ value: String, unit: String, width: CGFloat, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Spacer(minLength: 0)
            Text(value)
                .foregroundStyle(color)
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(width: width, alignment: .trailing)
    }
}
