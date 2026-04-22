import Foundation

struct TypingStats: Codable, Identifiable, Sendable {
    var id: String { date }

    let date: String
    let createdAt: Int64
    let updatedAt: Int64
    let chars: Int
    let charsCjk: Int
    let charsAscii: Int
    let commits: Int
    let avgWordLength: Double
    let charsPerMinute: Int
    let currentCpm: Int
    let peakCpm: Int
    let burstCpm: Int
    let activeMinutes: Double
    let newWordsCount: Int
    let newWords: [String]

    // 超过该时间未更新，实时速度视为 0，避免展示陈旧速度
    private static let currentCpmStaleMs: Int64 = 15_000
    // 低于该值认为不是 Unix 毫秒时间戳（例如旧版本写入的单调时间）
    private static let epochLowerBoundMs: Int64 = 946_684_800_000 // 2000-01-01

    var liveCurrentCpm: Int {
        guard updatedAt >= Self.epochLowerBoundMs else { return currentCpm }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        return nowMs - updatedAt > Self.currentCpmStaleMs ? 0 : currentCpm
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case chars
        case charsCjk = "chars_cjk"
        case charsAscii = "chars_ascii"
        case wordsEn = "words_en"
        case commits
        case avgWordLength = "avg_word_length"
        case charsPerMinute = "chars_per_minute"
        case currentCpm = "current_cpm"
        case peakCpm = "peak_cpm"
        case burstCpm = "burst_cpm"
        case activeMinutes = "active_minutes"
        case newWordsCount = "new_words_count"
        case newWords = "new_words"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(chars, forKey: .chars)
        try c.encode(charsCjk, forKey: .charsCjk)
        try c.encode(charsAscii, forKey: .charsAscii)
        try c.encode(commits, forKey: .commits)
        try c.encode(avgWordLength, forKey: .avgWordLength)
        try c.encode(charsPerMinute, forKey: .charsPerMinute)
        try c.encode(currentCpm, forKey: .currentCpm)
        try c.encode(peakCpm, forKey: .peakCpm)
        try c.encode(burstCpm, forKey: .burstCpm)
        try c.encode(activeMinutes, forKey: .activeMinutes)
        try c.encode(newWordsCount, forKey: .newWordsCount)
        try c.encode(newWords, forKey: .newWords)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        updatedAt = try c.decode(Int64.self, forKey: .updatedAt)
        chars = try c.decode(Int.self, forKey: .chars)
        charsCjk = try c.decode(Int.self, forKey: .charsCjk)
        // chars_ascii 是新主字段；words_en 是旧版字段名（历史 JSONL 里存的是英文词数，
        // 口径已变但留作 fallback，以便读旧历史行不至于失败）
        charsAscii = try (try? c.decode(Int.self, forKey: .charsAscii))
                     ?? c.decode(Int.self, forKey: .wordsEn)
        commits = try c.decode(Int.self, forKey: .commits)
        avgWordLength = try c.decode(Double.self, forKey: .avgWordLength)
        charsPerMinute = try c.decode(Int.self, forKey: .charsPerMinute)
        currentCpm = (try? c.decode(Int.self, forKey: .currentCpm)) ?? charsPerMinute
        peakCpm = try c.decode(Int.self, forKey: .peakCpm)
        burstCpm = (try? c.decode(Int.self, forKey: .burstCpm)) ?? 0
        activeMinutes = try c.decode(Double.self, forKey: .activeMinutes)
        newWordsCount = try c.decode(Int.self, forKey: .newWordsCount)
        newWords = try c.decode([String].self, forKey: .newWords)
    }

    /// For testing and programmatic creation
    init(
        date: String, createdAt: Int64 = 0, updatedAt: Int64 = 0,
        chars: Int = 0, charsCjk: Int = 0, charsAscii: Int = 0,
        commits: Int = 0, avgWordLength: Double = 0,
        charsPerMinute: Int = 0, currentCpm: Int? = nil, peakCpm: Int = 0,
        burstCpm: Int = 0,
        activeMinutes: Double = 0, newWordsCount: Int = 0, newWords: [String] = []
    ) {
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chars = chars
        self.charsCjk = charsCjk
        self.charsAscii = charsAscii
        self.commits = commits
        self.avgWordLength = avgWordLength
        self.charsPerMinute = charsPerMinute
        self.currentCpm = currentCpm ?? charsPerMinute
        self.peakCpm = peakCpm
        self.burstCpm = burstCpm
        self.activeMinutes = activeMinutes
        self.newWordsCount = newWordsCount
        self.newWords = newWords
    }
}
