import SwiftUI

struct TotalStatsView: View {
    let today: TypingStats?
    let history: [TypingStats]

    private var allRecords: [TypingStats] {
        var records = history
        if let today, !records.contains(where: { $0.date == today.date }) {
            records.append(today)
        }
        return records
    }

    private var totalChars: Int { allRecords.reduce(0) { $0 + $1.chars } }
    private var totalMinutes: Double { allRecords.reduce(0) { $0 + $1.activeMinutes } }
    private var totalCommits: Int { allRecords.reduce(0) { $0 + $1.commits } }
    private var totalDays: Int { allRecords.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("累计统计（\(totalDays) 天）")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)

            HStack(spacing: 0) {
                Text("\(compact(totalChars)) 字")
                    .frame(maxWidth: .infinity, alignment: .center)
                divider
                Text(formattedDuration(totalMinutes))
                    .frame(maxWidth: .infinity, alignment: .center)
                divider
                Text("\(compact(totalCommits)) 提交")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 14)
    }

    private func compact(_ n: Int) -> String {
        if n >= 100_000_000 {
            return String(format: "%.1f亿", Double(n) / 100_000_000)
        } else if n >= 10_000 {
            return String(format: "%.1f万", Double(n) / 10_000)
        } else if n >= 1_000 {
            return String(format: "%.1f千", Double(n) / 1_000)
        }
        return "\(n)"
    }

    private func formattedDuration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours) 时 \(mins) 分"
        }
        return String(format: "%.0f 分钟", minutes)
    }
}
