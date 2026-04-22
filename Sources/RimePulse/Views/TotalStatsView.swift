import Charts
import SwiftUI

struct TotalStatsView: View {
    let today: TypingStats?
    /// 预解析好的日记录（date 已是 Date），来自 StatsReader 缓存
    let trendDaily: [DailyStats]

    @State private var selectedMetric: TrendMetric = .totalChars
    @State private var selectedRange: TimeRange = .month
    @State private var hoverDate: Date? = nil
    @Namespace private var metricGlass

    /// 聚合结果缓存：只在 (trendDaily / selectedRange) 变化时重算
    @State private var aggregatedCache: AggregatedCache = .empty

    /// 首次打开菜单栏时延迟渲染主 Chart，避免 Charts 框架 + Metal shader
    /// 首次加载阻塞首帧。其余内容（today、总计条、自绘 sparkline）先出。
    @State private var showMainChart = false

    private static let calendar = Calendar.autoupdatingCurrent
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

    private var aggregatedRecords: [AggregatedRecord] { aggregatedCache.records }
    private var granularity: TrendGranularity { aggregatedCache.granularity }

    private func rebuildAggregatedCache() {
        let sorted = trendDaily
        let ranged: [DailyStats]
        switch selectedRange {
        case .week:  ranged = Array(sorted.suffix(7))
        case .month: ranged = Array(sorted.suffix(30))
        case .all:   ranged = sorted
        }

        let gran: TrendGranularity = switch selectedRange {
        case .week, .month: .day
        case .all:          TrendGranularity.auto(for: ranged.map(\.day), calendar: Self.calendar)
        }

        guard !ranged.isEmpty else {
            aggregatedCache = AggregatedCache(records: [], granularity: gran)
            return
        }

        var buckets: [Date: AggregateAccumulator] = [:]
        var bucketOrder: [Date] = []
        for record in ranged {
            let bucketDate = gran.bucketStart(for: record.day, calendar: Self.calendar)
            if buckets[bucketDate] == nil { bucketOrder.append(bucketDate) }
            var acc = buckets[bucketDate] ?? AggregateAccumulator()
            acc.add(record.stats)
            buckets[bucketDate] = acc
        }

        let records = bucketOrder.map { key in buckets[key]!.makeRecord(at: key) }
        aggregatedCache = AggregatedCache(records: records, granularity: gran)
    }

    /// 聚合签名：只在实际影响聚合结果的值变化时为新
    private var aggregationSignature: String {
        guard let first = trendDaily.first, let last = trendDaily.last else { return "empty" }
        return "\(trendDaily.count)|\(first.day.timeIntervalSince1970)|\(last.day.timeIntervalSince1970)|\(last.stats.updatedAt)|\(selectedRange.rawValue)"
    }

    // MARK: - Totals

    private var totalChars: Int { aggregatedRecords.reduce(0) { $0 + $1.chars } }
    private var totalMinutes: Double { aggregatedRecords.reduce(0) { $0 + $1.activeMinutes } }
    private var totalCommits: Int { aggregatedRecords.reduce(0) { $0 + $1.commits } }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.padding(.horizontal, 10)
            metricTabs.padding(.horizontal, 10)
            mainChart.padding(.horizontal, 10)
            sparklineRows.padding(.horizontal, 10)
            totalsBar.padding(.horizontal, 10)
        }
        .onAppear { rebuildAggregatedCache() }
        .task {
            // 首帧先让轻量内容（today / sparkline / 总计条）上屏，
            // 再在下一帧实例化 Swift Charts — 用户感知是瞬开+图表渐入。
            try? await Task.sleep(for: .milliseconds(16))
            showMainChart = true
        }
        .onChange(of: aggregationSignature) { _, _ in
            rebuildAggregatedCache()
        }
    }

    // MARK: - Header

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
                ForEach(Array(TrendMetric.mainTabs.enumerated()), id: \.element) { index, metric in
                    MetricTabButton(
                        title: metric.title,
                        isOn: selectedMetric == metric,
                        tint: metric.color,
                        shortcut: KeyEquivalent(Character("\(index + 1)")),
                        glassID: metric,
                        namespace: metricGlass
                    ) {
                        selectedMetric = metric
                    }
                }
            }
            .padding(2)
            .background(Capsule().fill(.quaternary.opacity(0.4)))
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
        guard let today,
              let todayDay = trendDaily.last(where: { $0.stats.date == today.date })?.day
        else { return nil }
        let bucket = granularity.bucketStart(for: todayDay, calendar: Self.calendar)
        return aggregatedRecords.firstIndex(where: { $0.date == bucket })
    }

    private var mainChartMaxValue: Double {
        let max = aggregatedRecords.map { selectedMetric.value(from: $0) }.max() ?? 0
        return max <= 0 ? 1 : max
    }

    private var hoveredRecord: AggregatedRecord? {
        guard let hoverDate else { return nil }
        return aggregatedRecords.min {
            abs($0.date.timeIntervalSince(hoverDate)) < abs($1.date.timeIntervalSince(hoverDate))
        }
    }

    private var displayRecord: AggregatedRecord? {
        if let r = hoveredRecord { return r }
        if let peakIndex { return aggregatedRecords[peakIndex] }
        return nil
    }

    private var headlineNumeric: Double {
        guard let r = displayRecord else { return 0 }
        return selectedMetric.value(from: r)
    }

    private var headlineLabel: String {
        hoveredRecord != nil ? dateLabel(for: hoveredRecord!.date) : "峰值"
    }

    private var mainChart: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Spacer()
                Text("\(headlineLabel) ")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
                Text(formatHeadline(headlineNumeric))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.snappy(duration: 0.25), value: headlineNumeric)
                Text(" \(selectedMetric.unit)")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            chartBody
                .frame(height: 76)
                .animation(.snappy(duration: 0.28), value: selectedMetric)
                .animation(.snappy(duration: 0.28), value: selectedRange)
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        if aggregatedRecords.isEmpty {
            ContentUnavailableView {
                Label("暂无数据", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .controlSize(.mini)
        } else if showMainChart {
            mainChartCore
                .transition(.opacity)
        } else {
            Color.clear
        }
    }

    private var mainChartCore: some View {
        Chart {
            ForEach(aggregatedRecords, id: \.date) { record in
                BarMark(
                    x: .value("日期", record.date, unit: .day),
                    y: .value("值", selectedMetric.value(from: record)),
                    width: .ratio(0.72)
                )
                .foregroundStyle(barStyle(for: record))
                .cornerRadius(2)
            }

        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { value in
                AxisValueLabel(collisionResolution: .disabled) {
                    if let date = value.as(Date.self) {
                        Text(dateLabel(for: date))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(mainChartMaxValue * 1.10))
        .chartXSelection(value: $hoverDate)
    }

    private func barStyle(for record: AggregatedRecord) -> Color {
        let accent = selectedMetric.color
        if let hovered = hoveredRecord {
            return record.date == hovered.date ? accent : accent.opacity(0.22)
        }
        if let peakIndex, aggregatedRecords[peakIndex].date == record.date {
            return accent
        }
        if let todayIndex, aggregatedRecords[todayIndex].date == record.date {
            return accent.opacity(0.55)
        }
        return Color.primary.opacity(0.18)
    }

private var xAxisDates: [Date] {
        let n = aggregatedRecords.count
        guard n > 0 else { return [] }
        if n == 1 { return [aggregatedRecords[0].date] }
        if n == 2 { return aggregatedRecords.map(\.date) }
        return [
            aggregatedRecords[0].date,
            aggregatedRecords[n / 2].date,
            aggregatedRecords[n - 1].date
        ]
    }

    private func dateLabel(for date: Date) -> String {
        switch granularity {
        case .day, .week: return Self.dayAxisFormatter.string(from: date)
        case .month:      return Self.monthAxisFormatter.string(from: date)
        case .year:       return Self.yearAxisFormatter.string(from: date)
        }
    }

    private func formatHeadline(_ v: Double) -> String {
        switch selectedMetric {
        case .charsPerMinute: return "\(Int(v.rounded()))"
        case .activeMinutes:  return String(format: "%.1f", v)
        default:              return compactNumber(Int(v.rounded()))
        }
    }

    // MARK: - Sparklines

    private var sparklineRows: some View {
        VStack(spacing: 2) {
            ForEach(TrendMetric.sparkRows) { metric in
                SparklineRow(metric: metric, records: aggregatedRecords)
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
