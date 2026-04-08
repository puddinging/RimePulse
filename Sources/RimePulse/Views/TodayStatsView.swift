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
                HStack(spacing: 4) {
                    Text("中文 \(stats.charsCjk)")
                        .foregroundStyle(MetricColors.charsCjk)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("英文 \(stats.wordsEn)")
                        .foregroundStyle(MetricColors.wordsEn)
                }
                .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            // 指标卡片
            SpeedMetricCard(current: stats.charsPerMinute, peak: stats.peakCpm, color: MetricColors.charsPerMinute)
            HStack(spacing: 6) {
                MetricCard(value: String(format: "%.1f", stats.activeMinutes), unit: "分钟", label: "活跃时长", color: MetricColors.activeMinutes)
                MetricCard(value: "\(stats.commits)", unit: "次", label: "提交", color: MetricColors.commits)
            }
        }
        .padding(10)
    }
}

private struct SpeedMetricCard: View {
    let current: Int
    let peak: Int
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(current)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("/")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(peak)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("字/分")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text("当前/峰值")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
