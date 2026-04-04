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
        Grid(alignment: .trailing, horizontalSpacing: 4) {
            GridRow {
                Text(shortDate)
                    .gridColumnAlignment(.leading)
                Text("\(stats.chars)字")
                Text("\(stats.charsPerMinute)/分")
                    .foregroundStyle(.orange)
                Text(String(format: "%.0f分钟", stats.activeMinutes))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }
}
