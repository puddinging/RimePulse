import SwiftUI

struct TodayStatsView: View {
    let stats: TypingStats

    var body: some View {
        VStack(spacing: 10) {
            Text("今日")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 核心数据
            VStack(spacing: 1) {
                Text("\(stats.chars)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("中文 \(stats.charsCjk)  ·  英文 \(stats.wordsEn)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            // 四指标卡片
            HStack(spacing: 6) {
                MetricCard(value: "\(stats.charsPerMinute)", unit: "字/分", label: "速度", color: .orange)
                MetricCard(value: "\(stats.peakCpm)", unit: "字/分", label: "峰值", color: .red)
            }
            HStack(spacing: 6) {
                MetricCard(value: String(format: "%.1f", stats.activeMinutes), unit: "分钟", label: "活跃时长", color: .blue)
                MetricCard(value: "\(stats.commits)", unit: "次", label: "提交", color: .green)
            }

            if stats.newWordsCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    Text("新造词 \(stats.newWordsCount) 个")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(10)
    }
}

private struct MetricCard: View {
    let value: String
    let unit: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
