import Foundation
import Observation
import os.log

@Observable
@MainActor
final class StatsReader {
    private(set) var today: TypingStats?
    private(set) var history: [TypingStats] = []

    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var dirDescriptor: Int32 = -1
    private var lastUpdatedAt: Int64 = 0
    private let dataDir: String
    private let todayPath: String

    private static let todayFile = "typing_stats_today.json"
    private static let historyFile = "typing_stats.jsonl"
    private static let logger = Logger(subsystem: "im.rime.RimePulse", category: "StatsReader")
    private static let maxRetryDelay: TimeInterval = 30

    private static let configPath = NSHomeDirectory() + "/.config/rimestats/config.json"
    private static let defaultDataDir = NSHomeDirectory() + "/Library/Rime"

    init() {
        dataDir = Self.resolveDataDir()
        todayPath = "\(dataDir)/\(Self.todayFile)"
        loadAll()
        startWatching()
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
        if fileDescriptor >= 0 { close(fileDescriptor) }
        if dirDescriptor >= 0 { close(dirDescriptor) }
        fileSource = nil
        dirSource = nil
        fileDescriptor = -1
        dirDescriptor = -1
    }

    private func startWatching() {
        // 尝试监听文件本身（write 事件）
        if watchFile() { return }
        // 文件不存在时，监听目录等待文件创建
        watchDirectory()
    }

    private func watchFile() -> Bool {
        let fd = open(todayPath, O_EVTONLY)
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
            if FileManager.default.fileExists(atPath: self.todayPath) {
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
        guard let data = FileManager.default.contents(atPath: todayPath) else {
            today = nil
            lastUpdatedAt = 0
            return
        }

        let stats: TypingStats
        do {
            stats = try JSONDecoder().decode(TypingStats.self, from: data)
        } catch {
            Self.logger.error("Failed to decode \(Self.todayFile): \(error.localizedDescription)")
            return
        }

        if stats.updatedAt != lastUpdatedAt {
            lastUpdatedAt = stats.updatedAt
            today = stats
            loadHistory()
        }
    }

    private func loadHistory() {
        let path = "\(dataDir)/\(Self.historyFile)"
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            history = []
            return
        }

        let decoder = JSONDecoder()
        var result: [TypingStats] = []

        for (index, line) in content.components(separatedBy: "\n").enumerated() where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }
            do {
                result.append(try decoder.decode(TypingStats.self, from: lineData))
            } catch {
                Self.logger.error("Failed to decode \(Self.historyFile) line \(index + 1): \(error.localizedDescription)")
            }
        }

        // 最近 7 天，按日期倒序
        history = Array(result.suffix(7).reversed())
    }
}
