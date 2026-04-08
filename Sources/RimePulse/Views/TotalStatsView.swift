import Charts
import SwiftUI

struct TotalStatsView: View {
    let today: TypingStats?
    let trendHistory: [TypingStats]

    private static let calendar = Calendar.autoupdatingCurrent
    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let dayAxisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    private static let monthAxisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yy/MM"
        return formatter
    }()
    private static let yearAxisFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy"
        return formatter
    }()

    private var allRecords: [TypingStats] {
        var records = trendHistory
        if let today, !records.contains(where: { $0.date == today.date }) {
            records.append(today)
        }
        return records
    }

    private var dailyRecords: [DatedStats] {
        var latestByDate: [String: TypingStats] = [:]
        for record in allRecords {
            if let old = latestByDate[record.date] {
                if record.updatedAt >= old.updatedAt {
                    latestByDate[record.date] = record
                }
            } else {
                latestByDate[record.date] = record
            }
        }

        var result: [DatedStats] = []
        for (dateString, stats) in latestByDate {
            if let date = Self.dayParser.date(from: dateString) {
                result.append(DatedStats(date: date, stats: stats))
            }
        }
        result.sort { $0.date < $1.date }
        return result
    }

    private var totalChars: Int { dailyRecords.reduce(0) { $0 + $1.stats.chars } }
    private var totalMinutes: Double { dailyRecords.reduce(0) { $0 + $1.stats.activeMinutes } }
    private var totalCommits: Int { dailyRecords.reduce(0) { $0 + $1.stats.commits } }
    private var totalDays: Int { dailyRecords.count }

    private var granularity: TrendGranularity {
        TrendGranularity.auto(for: dailyRecords.map(\.date), calendar: Self.calendar)
    }

    private var aggregatedRecords: [AggregatedRecord] {
        guard !dailyRecords.isEmpty else { return [] }

        var buckets: [Date: AggregateAccumulator] = [:]
        for record in dailyRecords {
            let bucketDate = granularity.bucketStart(for: record.date, calendar: Self.calendar)
            var acc = buckets[bucketDate] ?? AggregateAccumulator()
            acc.add(record.stats)
            buckets[bucketDate] = acc
        }

        return buckets.keys.sorted().map { key in
            buckets[key]!.makeRecord(at: key)
        }
    }

    private var chartPoints: [TrendPoint] {
        let records = aggregatedRecords
        guard !records.isEmpty else { return [] }

        var points: [TrendPoint] = []
        for metric in TrendMetric.allCases {
            let values = records.map { metric.value(from: $0) }
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 0
            let span = maxValue - minValue

            for (index, record) in records.enumerated() {
                let value = values[index]
                let normalized = span > 0 ? ((value - minValue) / span * 100) : 50
                points.append(TrendPoint(
                    id: "\(metric.id)-\(record.date.timeIntervalSince1970)",
                    date: record.date,
                    metric: metric,
                    normalizedValue: normalized
                ))
            }
        }
        return points
    }

    private var xAxisStrideCount: Int {
        max(1, Int(ceil(Double(aggregatedRecords.count) / 6)))
    }

    private var shouldShowPoints: Bool {
        aggregatedRecords.count <= 90
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("累计趋势（\(totalDays) 天）")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("按\(granularity.label)汇总")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)

            Chart(chartPoints) { point in
                LineMark(
                    x: .value("日期", point.date),
                    y: .value("相对值", point.normalizedValue),
                    series: .value("指标", point.metric.title)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .foregroundStyle(point.metric.color)

                if shouldShowPoints {
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("相对值", point.normalizedValue)
                    )
                    .symbolSize(10)
                    .foregroundStyle(point.metric.color)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: granularity.axisComponent, count: xAxisStrideCount)) { value in
                    AxisGridLine()
                        .foregroundStyle(.quaternary.opacity(0.3))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(axisLabelText(for: date))
                                .font(.system(size: 8, design: .monospaced))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .frame(height: 116)
            .padding(.horizontal, 10)

            legend

            HStack(spacing: 0) {
                Text("\(compactNumber(totalChars)) 字")
                    .frame(maxWidth: .infinity, alignment: .center)
                divider
                Text(formattedDuration(totalMinutes))
                    .frame(maxWidth: .infinity, alignment: .center)
                divider
                Text("\(compactNumber(totalCommits)) 提交")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
        }
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
            ForEach(TrendMetric.allCases) { metric in
                HStack(spacing: 4) {
                    Circle()
                        .fill(metric.color)
                        .frame(width: 5, height: 5)
                    Text(metric.title)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 0.5, height: 14)
    }

    private func axisLabelText(for date: Date) -> String {
        switch granularity {
        case .day, .week:
            return Self.dayAxisFormatter.string(from: date)
        case .month:
            return Self.monthAxisFormatter.string(from: date)
        case .year:
            return Self.yearAxisFormatter.string(from: date)
        }
    }
}

private struct DatedStats {
    let date: Date
    let stats: TypingStats
}

private struct AggregateAccumulator {
    var chars: Int = 0
    var charsCjk: Int = 0
    var wordsEn: Int = 0
    var activeMinutes: Double = 0
    var commits: Int = 0

    mutating func add(_ stats: TypingStats) {
        chars += stats.chars
        charsCjk += stats.charsCjk
        wordsEn += stats.wordsEn
        activeMinutes += stats.activeMinutes
        commits += stats.commits
    }

    func makeRecord(at date: Date) -> AggregatedRecord {
        let cpm = activeMinutes > 0 ? Int((Double(chars) / activeMinutes).rounded(.down)) : 0
        return AggregatedRecord(
            date: date,
            chars: chars,
            charsCjk: charsCjk,
            wordsEn: wordsEn,
            activeMinutes: activeMinutes,
            commits: commits,
            charsPerMinute: cpm
        )
    }
}

private struct AggregatedRecord {
    let date: Date
    let chars: Int
    let charsCjk: Int
    let wordsEn: Int
    let activeMinutes: Double
    let commits: Int
    let charsPerMinute: Int
}

private struct TrendPoint: Identifiable {
    let id: String
    let date: Date
    let metric: TrendMetric
    let normalizedValue: Double
}

private enum TrendGranularity {
    case day
    case week
    case month
    case year

    static func auto(for dates: [Date], calendar: Calendar) -> Self {
        guard let firstRaw = dates.first, let lastRaw = dates.last else { return .day }
        let first = calendar.startOfDay(for: firstRaw)
        let last = calendar.startOfDay(for: lastRaw)

        let dayCount = max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)
        let weekCount = Int(ceil(Double(dayCount) / 7.0))
        let monthCount = max(1, (calendar.dateComponents([.month], from: first, to: last).month ?? 0) + 1)

        // 目标：保持视图可读，短时间自然铺满，长时间自动压缩。
        let targetBucketCount = 60
        if dayCount <= targetBucketCount { return .day }
        if weekCount <= targetBucketCount { return .week }
        if monthCount <= targetBucketCount { return .month }
        return .year
    }

    var label: String {
        switch self {
        case .day: "天"
        case .week: "周"
        case .month: "月"
        case .year: "年"
        }
    }

    var axisComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    func bucketStart(for date: Date, calendar: Calendar) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date)) ?? calendar.startOfDay(for: date)
        }
    }
}

private enum TrendMetric: String, CaseIterable, Identifiable {
    case totalChars
    case charsCjk
    case wordsEn
    case activeMinutes
    case commits
    case charsPerMinute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalChars: "总量"
        case .charsCjk: "中文"
        case .wordsEn: "英文"
        case .activeMinutes: "活跃时长"
        case .commits: "总提交"
        case .charsPerMinute: "平均速度"
        }
    }

    var color: Color {
        switch self {
        case .totalChars: MetricColors.totalChars
        case .charsCjk: MetricColors.charsCjk
        case .wordsEn: MetricColors.wordsEn
        case .activeMinutes: MetricColors.activeMinutes
        case .commits: MetricColors.commits
        case .charsPerMinute: MetricColors.charsPerMinute
        }
    }

    func value(from stats: AggregatedRecord) -> Double {
        switch self {
        case .totalChars:
            return Double(stats.chars)
        case .charsCjk:
            return Double(stats.charsCjk)
        case .wordsEn:
            return Double(stats.wordsEn)
        case .activeMinutes:
            return stats.activeMinutes
        case .commits:
            return Double(stats.commits)
        case .charsPerMinute:
            return Double(stats.charsPerMinute)
        }
    }
}
