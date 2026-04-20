import SwiftUI

struct TodayStatsView: View {
    let stats: TypingStats

    var body: some View {
        VStack(spacing: 9) {
            // 核心数据
            VStack(spacing: 1) {
                Text(compactNumber(stats.chars))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.snappy(duration: 0.3), value: stats.chars)

                HStack(spacing: 8) {
                    CategoryLabel(
                        color: MetricColors.charsCjk,
                        title: "中文",
                        value: compactNumber(stats.charsCjk)
                    )
                    Text("·")
                        .foregroundStyle(.tertiary)
                    CategoryLabel(
                        color: MetricColors.wordsEn,
                        title: "英文",
                        value: compactNumber(stats.wordsEn)
                    )
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)

            // 指标卡片 — tint 跟随对应 metric 颜色
            SpeedMetricCard(
                current: stats.liveCurrentCpm,
                peak: stats.peakCpm,
                tint: MetricColors.charsPerMinute
            )
            HStack(spacing: 6) {
                MetricCard(
                    value: String(format: "%.1f", stats.activeMinutes),
                    unit: "分钟",
                    label: "活跃时长",
                    tint: MetricColors.activeMinutes
                )
                MetricCard(
                    value: compactNumber(stats.commits),
                    unit: "次",
                    label: "提交",
                    tint: MetricColors.commits
                )
            }
        }
        .padding(10)
    }
}

private struct CategoryLabel: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(title) \(value)")
        }
    }
}

private struct SpeedMetricCard: View {
    let current: Int
    let peak: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(current)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("/")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("\(peak)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("字/分")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text("当前 / 峰值")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(tintedCardBackground(tint))
    }
}

private struct MetricCard: View {
    let value: String
    let unit: String
    let label: String
    let tint: Color

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
        .background(tintedCardBackground(tint))
    }
}

@ViewBuilder
private func tintedCardBackground(_ tint: Color) -> some View {
    RoundedRectangle(cornerRadius: 6)
        .fill(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.22), lineWidth: 0.5)
        )
}
