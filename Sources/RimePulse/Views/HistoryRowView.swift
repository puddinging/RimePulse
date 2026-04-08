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
                .frame(width: 34, alignment: .leading)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("\(stats.chars)字")
                .frame(width: 52, alignment: .trailing)

            Text("\(stats.charsPerMinute)/分")
                .frame(width: 56, alignment: .trailing)
                .foregroundStyle(.orange)

            Text(String(format: "%.0f分", stats.activeMinutes))
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .monospacedDigit()
        .lineLimit(1)
    }
}
