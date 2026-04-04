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
        HStack(spacing: 0) {
            Text(shortDate)
                .frame(width: 38, alignment: .leading)
            Text("\(stats.chars)字")
                .frame(width: 46, alignment: .trailing)
            Text("\(stats.charsPerMinute)/分")
                .foregroundStyle(.orange)
                .frame(width: 38, alignment: .trailing)
            Text(String(format: "%.0f分钟", stats.activeMinutes))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }
}
