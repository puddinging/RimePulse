import Foundation
import SwiftUI

// MARK: - TimeRange

enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case week = "7D"
    case month = "30D"
    case all = "ALL"

    var id: Self { self }
    var label: String { rawValue }
}

// MARK: - TrendMetric (unified)

/// 统一的指标枚举 — 覆盖主图 tab + 小倍图（sparkline）两个用途
enum TrendMetric: String, Hashable, CaseIterable, Identifiable, Sendable {
    case totalChars
    case charsCjk
    case wordsEn
    case charsPerMinute
    case activeMinutes
    case commits

    var id: Self { self }

    /// 主图表 tab 位集合（不含 activeMinutes — 时长用 sparkline 展示即可）
    static let mainTabs: [TrendMetric] = [
        .totalChars, .charsCjk, .wordsEn, .charsPerMinute, .commits
    ]

    /// Sparkline 行集合（不含 totalChars — 是所有分量之和）
    static let sparkRows: [TrendMetric] = [
        .charsCjk, .wordsEn, .charsPerMinute, .activeMinutes, .commits
    ]

    var title: String {
        switch self {
        case .totalChars:     return "字数"
        case .charsCjk:       return "中文"
        case .wordsEn:        return "英文"
        case .charsPerMinute: return "速度"
        case .activeMinutes:  return "时长"
        case .commits:        return "提交"
        }
    }

    var unit: String {
        switch self {
        case .totalChars, .charsCjk: return "字"
        case .wordsEn:        return "词"
        case .charsPerMinute: return "字/分"
        case .activeMinutes:  return "分钟"
        case .commits:        return "次"
        }
    }

    var color: Color {
        switch self {
        case .totalChars:     return .primary
        case .charsCjk:       return MetricColors.charsCjk
        case .wordsEn:        return MetricColors.wordsEn
        case .charsPerMinute: return MetricColors.charsPerMinute
        case .activeMinutes:  return MetricColors.activeMinutes
        case .commits:        return MetricColors.commits
        }
    }

    func value(from r: AggregatedRecord) -> Double {
        switch self {
        case .totalChars:     return Double(r.chars)
        case .charsCjk:       return Double(r.charsCjk)
        case .wordsEn:        return Double(r.wordsEn)
        case .charsPerMinute: return Double(r.charsPerMinute)
        case .activeMinutes:  return r.activeMinutes
        case .commits:        return Double(r.commits)
        }
    }

    /// 单条记录的展示值（用于主图 headline / hover tooltip）
    func formattedValue(from r: AggregatedRecord) -> String {
        let v = value(from: r)
        switch self {
        case .charsPerMinute: return "\(Int(v.rounded()))"
        case .activeMinutes:  return String(format: "%.1f", v)
        default:              return compactNumber(Int(v.rounded()))
        }
    }

    /// 所选区间的累计/平均（用于 sparkline 行尾值、底部总计）
    func totalFormatted(from records: [AggregatedRecord]) -> String {
        switch self {
        case .totalChars:
            return compactNumber(records.reduce(0) { $0 + $1.chars })
        case .charsCjk:
            return compactNumber(records.reduce(0) { $0 + $1.charsCjk })
        case .wordsEn:
            return compactNumber(records.reduce(0) { $0 + $1.wordsEn })
        case .charsPerMinute:
            let xs = records.map(\.charsPerMinute).filter { $0 > 0 }
            guard !xs.isEmpty else { return "0" }
            let avg = xs.reduce(0, +) / xs.count
            return "\(avg)/分"
        case .activeMinutes:
            return formattedDuration(records.reduce(0) { $0 + $1.activeMinutes })
        case .commits:
            return compactNumber(records.reduce(0) { $0 + $1.commits })
        }
    }
}

// MARK: - Aggregation

struct AggregatedRecord: Hashable, Sendable {
    let date: Date
    let chars: Int
    let charsCjk: Int
    let wordsEn: Int
    let activeMinutes: Double
    let commits: Int
    let charsPerMinute: Int
}

struct AggregatedCache: Sendable {
    let records: [AggregatedRecord]
    let granularity: TrendGranularity

    static let empty = AggregatedCache(records: [], granularity: .day)
}

struct AggregateAccumulator {
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

// MARK: - Granularity

enum TrendGranularity: Sendable {
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
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
                ?? calendar.startOfDay(for: date)
        case .year:
            return calendar.date(from: calendar.dateComponents([.year], from: date))
                ?? calendar.startOfDay(for: date)
        }
    }
}
