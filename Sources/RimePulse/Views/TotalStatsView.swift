import Charts
import SwiftUI

struct TotalStatsView: View {
    let today: TypingStats?
    let trendHistory: [TypingStats]

    @State private var selectedMetric: MainMetric = .totalChars
    @State private var selectedRange: TimeRange = .month
    @Namespace private var metricGlass

    private static let calendar = Calendar.autoupdatingCurrent
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let dayAxisFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .autoupdatingCurrent
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "MM/dd"
        return f
    }()
    private static let monthAxisFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .autoupdatingCurrent
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yy/MM"
        return f
    }()
    private static let yearAxisFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .autoupdatingCurrent
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .autoupdatingCurrent
        f.dateFormat = "yyyy"
        return f
    }()

    // MARK: - Data pipeline

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

    private var rangedRecords: [DatedStats] {
        switch selectedRange {
        case .week:  return Array(dailyRecords.suffix(7))
        case .month: return Array(dailyRecords.suffix(30))
        case .all:   return dailyRecords
        }
    }

    private var granularity: TrendGranularity {
        switch selectedRange {
        case .week, .month:
            return .day
        case .all:
            return TrendGranularity.auto(for: rangedRecords.map(\.date), calendar: Self.calendar)
        }
    }

    private var aggregatedRecords: [AggregatedRecord] {
        guard !rangedRecords.isEmpty else { return [] }

        var buckets: [Date: AggregateAccumulator] = [:]
        for record in rangedRecords {
            let bucketDate = granularity.bucketStart(for: record.date, calendar: Self.calendar)
            var acc = buckets[bucketDate] ?? AggregateAccumulator()
            acc.add(record.stats)
            buckets[bucketDate] = acc
        }

        return buckets.keys.sorted().map { key in
            buckets[key]!.makeRecord(at: key)
        }
    }

    // MARK: - Totals

    private var totalChars: Int { aggregatedRecords.reduce(0) { $0 + $1.chars } }
    private var totalMinutes: Double { aggregatedRecords.reduce(0) { $0 + $1.activeMinutes } }
    private var totalCommits: Int { aggregatedRecords.reduce(0) { $0 + $1.commits } }
    private var totalDays: Int { aggregatedRecords.count }

    // MARK: - View

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
                .padding(.horizontal, 10)

            metricTabs
                .padding(.horizontal, 10)

            mainChart
                .padding(.horizontal, 10)

            sparklineRows
                .padding(.horizontal, 10)

            totalsBar
                .padding(.horizontal, 10)
        }
    }

    // MARK: - Header (title + period segmented)

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("趋势")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(headerSubtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            PeriodSegmented(selected: $selectedRange)
        }
    }

    private var headerSubtitle: String {
        guard let first = aggregatedRecords.first, let last = aggregatedRecords.last else {
            return ""
        }
        let range = "\(Self.dayAxisFormatter.string(from: first.date))→\(Self.dayAxisFormatter.string(from: last.date))"
        return "\(range) · 按\(granularity.label)"
    }

    // MARK: - Metric tabs

    private var metricTabs: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(MainMetric.allCases) { metric in
                    MetricTabButton(
                        title: metric.title,
                        isOn: selectedMetric == metric,
                        glassID: metric,
                        namespace: metricGlass
                    ) {
                        selectedMetric = metric
                    }
                }
            }
            .padding(2)
            .background(
                Capsule().fill(.quaternary.opacity(0.4))
            )
        }
        .animation(.snappy(duration: 0.22), value: selectedMetric)
    }

    // MARK: - Main chart

    private var peakIndex: Int? {
        guard !aggregatedRecords.isEmpty else { return nil }
        let values = aggregatedRecords.map { selectedMetric.value(from: $0) }
        guard let maxVal = values.max(), maxVal > 0 else { return nil }
        return values.firstIndex(of: maxVal)
    }

    private var todayIndex: Int? {
        guard let todayDate = today.flatMap({ Self.dayParser.date(from: $0.date) }) else {
            return nil
        }
        let bucket = granularity.bucketStart(for: todayDate, calendar: Self.calendar)
        return aggregatedRecords.firstIndex(where: { $0.date == bucket })
    }

    private var mainChartMaxValue: Double {
        let max = aggregatedRecords.map { selectedMetric.value(from: $0) }.max() ?? 0
        return max <= 0 ? 1 : max
    }

    private var headlineValue: String {
        guard let peakIndex else { return "—" }
        let r = aggregatedRecords[peakIndex]
        return selectedMetric.formattedValue(from: r)
    }

    private var mainChart: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Headline: peak value of the selected metric in selected range
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Spacer()
                Text("峰值 ")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(headlineValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(" \(selectedMetric.unit)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Chart {
                ForEach(Array(aggregatedRecords.enumerated()), id: \.offset) { index, record in
                    BarMark(
                        x: .value("序号", index),
                        y: .value("值", selectedMetric.value(from: record))
                    )
                    .foregroundStyle(barColor(for: index))
                    .cornerRadius(2)
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisLabelIndices) { value in
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let raw = value.as(Int.self) {
                            Text(axisLabelText(for: raw))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(mainChartMaxValue * 1.10))
            .frame(height: 72)
        }
    }

    private func barColor(for index: Int) -> Color {
        let isPeak = index == peakIndex
        let isToday = index == todayIndex
        let accent = selectedMetric.color
        if isPeak { return accent }
        if isToday { return accent.opacity(0.55) }
        return Color.primary.opacity(0.18)
    }

    private var xAxisLabelIndices: [Int] {
        let n = aggregatedRecords.count
        guard n > 0 else { return [] }
        if n == 1 { return [0] }
        if n == 2 { return [0, 1] }
        return [0, n / 2, n - 1]
    }

    private func axisLabelText(for index: Int) -> String {
        guard aggregatedRecords.indices.contains(index) else { return "" }
        let date = aggregatedRecords[index].date
        switch granularity {
        case .day, .week:
            return Self.dayAxisFormatter.string(from: date)
        case .month:
            return Self.monthAxisFormatter.string(from: date)
        case .year:
            return Self.yearAxisFormatter.string(from: date)
        }
    }

    // MARK: - Small multiples

    private var sparklineRows: some View {
        VStack(spacing: 2) {
            ForEach(SparkMetric.allCases) { metric in
                SparklineRow(
                    metric: metric,
                    records: aggregatedRecords
                )
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    // MARK: - Totals bar

    private var totalsBar: some View {
        HStack(spacing: 0) {
            TotalCell(label: "字数", value: compactNumber(totalChars))
            divider
            TotalCell(label: "时长", value: formattedDuration(totalMinutes))
            divider
            TotalCell(label: "提交", value: compactNumber(totalCommits))
        }
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 0.5, height: 16)
    }
}

// MARK: - Total cell

private struct TotalCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 8.5))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Period segmented (liquid glass pill)

private struct PeriodSegmented: View {
    @Binding var selected: TimeRange
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(TimeRange.allCases) { range in
                    segmentButton(for: range)
                }
            }
            .padding(2)
            .background(
                Capsule().fill(.quaternary.opacity(0.4))
            )
        }
        .animation(.snappy(duration: 0.22), value: selected)
    }

    private func segmentButton(for range: TimeRange) -> some View {
        let isOn = selected == range
        return Button {
            selected = range
        } label: {
            Text(range.label)
                .font(.system(size: 9.5, weight: isOn ? .semibold : .regular))
                .tracking(0.5)
                .foregroundStyle(isOn ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isOn ? Glass.regular.interactive() : Glass.identity,
            in: Capsule()
        )
        .glassEffectID(range, in: glass)
    }
}

// MARK: - Metric tab button

private struct MetricTabButton: View {
    let title: String
    let isOn: Bool
    let glassID: MainMetric
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                .tracking(0.2)
                .foregroundStyle(isOn ? .primary : .secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(
            isOn ? Glass.regular.interactive() : Glass.identity,
            in: Capsule()
        )
        .glassEffectID(glassID, in: namespace)
    }
}

// MARK: - Sparkline row

private struct SparklineRow: View {
    let metric: SparkMetric
    let records: [AggregatedRecord]

    private var values: [Double] { records.map { metric.value(from: $0) } }
    private var totalValue: String { metric.totalFormatted(from: records) }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(metric.color)
                .frame(width: 6, height: 6)

            Text(metric.title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

            sparkline
                .frame(height: 16)

            Text(totalValue)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(width: 62, alignment: .trailing)
        }
        .frame(height: 18)
    }

    private var sparkline: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let maxV = values.max() ?? 0
            let minV = values.min() ?? 0
            let span = max(maxV - minV, 0.0001)

            Path { path in
                for (i, v) in values.enumerated() {
                    let x = values.count <= 1 ? width / 2 :
                        width * CGFloat(i) / CGFloat(values.count - 1)
                    let normalized = maxV - minV == 0 ? 0.5 : (v - minV) / span
                    let y = height - (CGFloat(normalized) * (height - 2)) - 1
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(metric.color, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Enums

enum TimeRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case all = "ALL"

    var id: Self { self }
    var label: String { rawValue }
}

enum MainMetric: Hashable, CaseIterable, Identifiable {
    case totalChars, charsCjk, wordsEn, charsPerMinute, commits

    var id: Self { self }

    var title: String {
        switch self {
        case .totalChars:     return "字数"
        case .charsCjk:       return "中文"
        case .wordsEn:        return "英文"
        case .charsPerMinute: return "速度"
        case .commits:        return "提交"
        }
    }

    var unit: String {
        switch self {
        case .totalChars, .charsCjk: return "字"
        case .wordsEn:    return "词"
        case .charsPerMinute: return "字/分"
        case .commits:    return "次"
        }
    }

    var color: Color {
        switch self {
        case .totalChars:     return .primary
        case .charsCjk:       return MetricColors.charsCjk
        case .wordsEn:        return MetricColors.wordsEn
        case .charsPerMinute: return MetricColors.charsPerMinute
        case .commits:        return MetricColors.commits
        }
    }

    func value(from r: AggregatedRecord) -> Double {
        switch self {
        case .totalChars:     return Double(r.chars)
        case .charsCjk:       return Double(r.charsCjk)
        case .wordsEn:        return Double(r.wordsEn)
        case .charsPerMinute: return Double(r.charsPerMinute)
        case .commits:        return Double(r.commits)
        }
    }

    func formattedValue(from r: AggregatedRecord) -> String {
        let v = value(from: r)
        switch self {
        case .charsPerMinute: return "\(Int(v))"
        default:              return compactNumber(Int(v))
        }
    }
}

enum SparkMetric: Hashable, CaseIterable, Identifiable {
    case charsCjk, wordsEn, charsPerMinute, activeMinutes, commits

    var id: Self { self }

    var title: String {
        switch self {
        case .charsCjk:       return "中文"
        case .wordsEn:        return "英文"
        case .charsPerMinute: return "速度"
        case .activeMinutes:  return "时长"
        case .commits:        return "提交"
        }
    }

    var color: Color {
        switch self {
        case .charsCjk:       return MetricColors.charsCjk
        case .wordsEn:        return MetricColors.wordsEn
        case .charsPerMinute: return MetricColors.charsPerMinute
        case .activeMinutes:  return MetricColors.activeMinutes
        case .commits:        return MetricColors.commits
        }
    }

    func value(from r: AggregatedRecord) -> Double {
        switch self {
        case .charsCjk:       return Double(r.charsCjk)
        case .wordsEn:        return Double(r.wordsEn)
        case .charsPerMinute: return Double(r.charsPerMinute)
        case .activeMinutes:  return r.activeMinutes
        case .commits:        return Double(r.commits)
        }
    }

    func totalFormatted(from records: [AggregatedRecord]) -> String {
        switch self {
        case .charsCjk:
            return compactNumber(records.reduce(0) { $0 + $1.charsCjk })
        case .wordsEn:
            return compactNumber(records.reduce(0) { $0 + $1.wordsEn })
        case .charsPerMinute:
            // 展示区间内的平均速度
            let ms = records.map { $0.charsPerMinute }.filter { $0 > 0 }
            guard !ms.isEmpty else { return "0" }
            let avg = ms.reduce(0, +) / ms.count
            return "\(avg)/分"
        case .activeMinutes:
            return formattedDuration(records.reduce(0) { $0 + $1.activeMinutes })
        case .commits:
            return compactNumber(records.reduce(0) { $0 + $1.commits })
        }
    }
}

// MARK: - Aggregation types (internal)

private struct DatedStats {
    let date: Date
    let stats: TypingStats
}

struct AggregatedRecord {
    let date: Date
    let chars: Int
    let charsCjk: Int
    let wordsEn: Int
    let activeMinutes: Double
    let commits: Int
    let charsPerMinute: Int
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

enum TrendGranularity {
    case day, week, month, year

    static func auto(for dates: [Date], calendar: Calendar) -> Self {
        guard let firstRaw = dates.first, let lastRaw = dates.last else { return .day }
        let first = calendar.startOfDay(for: firstRaw)
        let last = calendar.startOfDay(for: lastRaw)
        let dayCount = max(1, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1)

        if dayCount <= 62 { return .day }
        if dayCount <= 540 { return .week }
        if dayCount <= 3650 { return .month }
        return .year
    }

    var label: String {
        switch self {
        case .day:   return "天"
        case .week:  return "周"
        case .month: return "月"
        case .year:  return "年"
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
