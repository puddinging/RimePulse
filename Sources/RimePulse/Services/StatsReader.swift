import Foundation
import Observation
import os.log

/// A parsed daily record with its Date pre-resolved.
/// Used by views to avoid re-parsing date strings on every body evaluation.
struct DailyStats: Sendable, Identifiable {
    let day: Date
    let stats: TypingStats
    var id: String { stats.date }
}

@Observable
@MainActor
final class StatsReader {
    private(set) var today: TypingStats?
    private(set) var history: [TypingStats] = []
    private(set) var trendHistory: [TypingStats] = []
    /// Sorted by day ascending; today's record (if any) is merged in-place.
    /// Consumers get pre-parsed Date + stats and should not need to re-parse.
    private(set) var trendDaily: [DailyStats] = []

    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var dayTickSource: DispatchSourceTimer?
    private var fileDescriptor: Int32 = -1
    private var dirDescriptor: Int32 = -1
    private var lastUpdatedAt: Int64 = 0
    private var currentDate: String
    private var staleTodayForHistory: TypingStats?
    private let dataDir: String
    private let todayPaths: [String]
    private let historyPaths: [String]

    // 历史 JSONL 行在写入后不变，缓存解析结果避免每次 today 更新全量重解析
    private var historicalByDate: [String: DailyStats] = [:]
    private var historySignature: HistorySignature?

    private struct HistorySignature: Equatable {
        let path: String
        let size: Int64
        let mtime: Date?
    }

    private static let todayFiles = ["typing_stats_today.txt", "typing_stats_today.json"]
    private static let historyFiles = ["typing_stats.txt", "typing_stats.jsonl"]
    private static let logger = Logger(subsystem: "im.rime.RimePulse", category: "StatsReader")
    private static let maxRetryDelay: TimeInterval = 30
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let configPath = NSHomeDirectory() + "/.config/rimestats/config.json"
    private static let defaultDataDir = NSHomeDirectory() + "/Library/Rime"

    init() {
        currentDate = Self.currentDateString()
        let resolvedDataDir = Self.resolveDataDir()
        dataDir = resolvedDataDir
        todayPaths = Self.todayFiles.map { "\(resolvedDataDir)/\($0)" }
        historyPaths = Self.historyFiles.map { "\(resolvedDataDir)/\($0)" }
        loadAll()
        startWatching()
        startDayTicker()
    }

    private static func resolveDataDir() -> String {
        if let data = FileManager.default.contents(atPath: configPath),
           let config = try? JSONDecoder().decode(Config.self, from: data),
           let dir = config.dataDir,
           !dir.isEmpty {
            let resolved = NSString(string: dir).expandingTildeInPath
            logger.info("Using custom data dir: \(resolved)")
            return resolved
        }
        return defaultDataDir
    }

    private struct Config: Codable {
        let dataDir: String?

        enum CodingKeys: String, CodingKey {
            case dataDir = "data_dir"
        }
    }

    func stop() {
        fileSource?.cancel()
        dirSource?.cancel()
        dayTickSource?.cancel()
        if fileDescriptor >= 0 { close(fileDescriptor) }
        if dirDescriptor >= 0 { close(dirDescriptor) }
        fileSource = nil
        dirSource = nil
        dayTickSource = nil
        fileDescriptor = -1
        dirDescriptor = -1
    }

    private static func currentDateString() -> String {
        dayFormatter.string(from: Date())
    }

    private static func filename(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func firstExistingPath(in paths: [String]) -> String? {
        for path in paths where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return nil
    }

    private func startDayTicker() {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + .seconds(60), repeating: .seconds(60))
        source.setEventHandler { [weak self] in
            self?.refreshForDayChangeIfNeeded()
        }
        source.resume()
        dayTickSource = source
    }

    private func refreshForDayChangeIfNeeded() {
        let nowDate = Self.currentDateString()
        guard nowDate != currentDate else { return }
        currentDate = nowDate
        loadAll()
    }

    private func startWatching() {
        // 尝试监听文件本身（write 事件）
        if watchFile() { return }
        // 文件不存在时，监听目录等待文件创建
        watchDirectory()
    }

    private func watchFile() -> Bool {
        let watchPath = firstExistingPath(in: todayPaths) ?? todayPaths[0]
        let fd = open(watchPath, O_EVTONLY)
        guard fd >= 0 else { return false }

        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // 文件被删除或重命名（Lua 写入可能先删后建），重新监听
                self.restartWatching()
            } else {
                self.loadToday()
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        fileSource = source
        fileDescriptor = -1 // fd 由 source cancel handler 管理
        return true
    }

    private func watchDirectory(retryDelay: TimeInterval = 1) {
        let fd = open(dataDir, O_EVTONLY)
        guard fd >= 0 else {
            // 目录打开失败，退避重试
            let nextDelay = min(retryDelay * 2, Self.maxRetryDelay)
            Self.logger.warning("Failed to open directory \(self.dataDir), retrying in \(retryDelay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                self?.watchDirectory(retryDelay: nextDelay)
            }
            return
        }

        dirDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            // 目录有变更，检查文件是否已创建
            if self.firstExistingPath(in: self.todayPaths) != nil {
                self.loadToday()
                // 仅在 watchFile 成功后才取消目录监听
                if self.watchFile() {
                    source.cancel()
                    self.dirSource = nil
                    self.dirDescriptor = -1
                }
            }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        dirSource = source
        dirDescriptor = -1
    }

    private func restartWatching() {
        fileSource?.cancel()
        fileSource = nil
        fileDescriptor = -1

        // 短暂延迟后重新监听，等 Lua 写入完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.loadToday()
            if !self.watchFile() {
                self.watchDirectory()
            }
        }
    }

    private func loadAll() {
        loadToday()
        loadHistory()
    }

    private func loadToday() {
        guard let todayPath = firstExistingPath(in: todayPaths),
              let data = FileManager.default.contents(atPath: todayPath) else {
            today = nil
            lastUpdatedAt = 0
            if staleTodayForHistory != nil {
                staleTodayForHistory = nil
                loadHistory()
            }
            return
        }

        let stats: TypingStats
        do {
            stats = try JSONDecoder().decode(TypingStats.self, from: data)
        } catch {
            Self.logger.error("Failed to decode \(Self.filename(from: todayPath)): \(error.localizedDescription)")
            return
        }

        let nowDate = Self.currentDateString()
        if stats.date != nowDate {
            currentDate = nowDate
            today = nil
            lastUpdatedAt = 0

            let shouldRefreshHistory =
                staleTodayForHistory?.date != stats.date ||
                staleTodayForHistory?.updatedAt != stats.updatedAt
            if shouldRefreshHistory {
                staleTodayForHistory = stats
                loadHistory()
            }
            return
        }

        if staleTodayForHistory != nil {
            staleTodayForHistory = nil
            loadHistory()
        }

        if stats.updatedAt != lastUpdatedAt || today?.date != stats.date {
            lastUpdatedAt = stats.updatedAt
            today = stats
            loadHistory()
        }
    }

    /// 确保 JSONL 历史解析结果是最新的；文件没变时直接复用缓存。
    /// 只有历史文件 size / mtime 变化才会触发全量 re-parse。
    private func refreshHistoryCacheIfNeeded() {
        guard let path = firstExistingPath(in: historyPaths) else {
            // 文件不存在 — 清空历史缓存
            historicalByDate = [:]
            historySignature = nil
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attrs?[.size] as? Int64) ?? -1
        let mtime = attrs?[.modificationDate] as? Date
        let sig = HistorySignature(path: path, size: size, mtime: mtime)

        if sig == historySignature {
            return                       // 未变 — 复用缓存
        }

        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return                       // 读取失败 — 保留旧缓存
        }

        let decoder = JSONDecoder()
        var latest: [String: DailyStats] = [:]
        for (index, line) in content.components(separatedBy: "\n").enumerated() where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }
            do {
                let record = try decoder.decode(TypingStats.self, from: lineData)
                guard let day = Self.dayFormatter.date(from: record.date) else { continue }
                if let old = latest[record.date], record.updatedAt < old.stats.updatedAt {
                    continue
                }
                latest[record.date] = DailyStats(day: day, stats: record)
            } catch {
                Self.logger.error("Failed to decode \(Self.filename(from: path)) line \(index + 1): \(error.localizedDescription)")
            }
        }

        historicalByDate = latest
        historySignature = sig
    }

    /// 合并历史缓存 + 当前 today(或 staleToday)，刷新对外发布的数组。
    /// 今天数据之外的历史项是 immutable 的，所以这是一次廉价的合并 + 排序。
    private func rebuildPublished() {
        var merged = historicalByDate

        if let stale = staleTodayForHistory,
           let day = Self.dayFormatter.date(from: stale.date) {
            merged[stale.date] = mergePreferNewer(
                DailyStats(day: day, stats: stale), into: merged[stale.date]
            )
        }

        if let today = self.today,
           let day = Self.dayFormatter.date(from: today.date) {
            merged[today.date] = mergePreferNewer(
                DailyStats(day: day, stats: today), into: merged[today.date]
            )
        }

        let sorted = merged.values.sorted { $0.day < $1.day }
        trendDaily = sorted
        trendHistory = sorted.map(\.stats)
        // 最近 7 天，按日期倒序
        history = Array(trendHistory.suffix(7).reversed())
    }

    private func mergePreferNewer(_ incoming: DailyStats, into existing: DailyStats?) -> DailyStats {
        guard let existing else { return incoming }
        return incoming.stats.updatedAt >= existing.stats.updatedAt ? incoming : existing
    }

    private func loadHistory() {
        refreshHistoryCacheIfNeeded()
        rebuildPublished()

        // JSONL 缺失且只有内存里的 staleToday 时：保证输出非空
        if historicalByDate.isEmpty,
           staleTodayForHistory == nil,
           today == nil {
            trendDaily = []
            trendHistory = []
            history = []
        }
    }
}
