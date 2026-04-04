import SwiftUI

struct HistoryListView: View {
    let history: [TypingStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近 7 天")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 3)

            Grid(alignment: .trailing, horizontalSpacing: 4) {
                ForEach(history) { day in
                    GridRow {
                        Text(shortDate(day.date))
                            .gridColumnAlignment(.leading)
                        Text("\(day.chars)字")
                        Text("\(day.charsPerMinute)/分")
                            .foregroundStyle(.orange)
                        Text(String(format: "%.0f分钟", day.activeMinutes))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
        }
    }

    private func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])-\(parts[2])"
        }
        return date
    }
}
