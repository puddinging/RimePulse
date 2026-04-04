import Foundation

struct TypingStats: Codable, Identifiable, Sendable {
    var id: String { date }

    let date: String
    let createdAt: Int64
    let updatedAt: Int64
    let chars: Int
    let charsCjk: Int
    let wordsEn: Int
    let commits: Int
    let avgWordLength: Double
    let charsPerMinute: Int
    let peakCpm: Int
    let activeMinutes: Double
    let newWordsCount: Int
    let newWords: [String]

    private enum CodingKeys: String, CodingKey {
        case date
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case chars
        case charsCjk = "chars_cjk"
        case wordsEn = "words_en"
        case charsAscii = "chars_ascii"
        case commits
        case avgWordLength = "avg_word_length"
        case charsPerMinute = "chars_per_minute"
        case peakCpm = "peak_cpm"
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
        try c.encode(wordsEn, forKey: .wordsEn)
        try c.encode(commits, forKey: .commits)
        try c.encode(avgWordLength, forKey: .avgWordLength)
        try c.encode(charsPerMinute, forKey: .charsPerMinute)
        try c.encode(peakCpm, forKey: .peakCpm)
        try c.encode(activeMinutes, forKey: .activeMinutes)
        try c.encode(newWordsCount, forKey: .newWordsCount)
        try c.encode(newWords, forKey: .newWords)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // date is the only truly required field — record identity
        date = try c.decode(String.self, forKey: .date)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        updatedAt = try c.decode(Int64.self, forKey: .updatedAt)
        chars = try c.decode(Int.self, forKey: .chars)
        charsCjk = try c.decode(Int.self, forKey: .charsCjk)
        // Legacy fallback: words_en ← chars_ascii (field renamed)
        wordsEn = try (try? c.decode(Int.self, forKey: .wordsEn))
                  ?? c.decode(Int.self, forKey: .charsAscii)
        commits = try c.decode(Int.self, forKey: .commits)
        avgWordLength = try c.decode(Double.self, forKey: .avgWordLength)
        charsPerMinute = try c.decode(Int.self, forKey: .charsPerMinute)
        peakCpm = try c.decode(Int.self, forKey: .peakCpm)
        activeMinutes = try c.decode(Double.self, forKey: .activeMinutes)
        newWordsCount = try c.decode(Int.self, forKey: .newWordsCount)
        newWords = try c.decode([String].self, forKey: .newWords)
    }

    /// For testing and programmatic creation
    init(
        date: String, createdAt: Int64 = 0, updatedAt: Int64 = 0,
        chars: Int = 0, charsCjk: Int = 0, wordsEn: Int = 0,
        commits: Int = 0, avgWordLength: Double = 0,
        charsPerMinute: Int = 0, peakCpm: Int = 0,
        activeMinutes: Double = 0, newWordsCount: Int = 0, newWords: [String] = []
    ) {
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.chars = chars
        self.charsCjk = charsCjk
        self.wordsEn = wordsEn
        self.commits = commits
        self.avgWordLength = avgWordLength
        self.charsPerMinute = charsPerMinute
        self.peakCpm = peakCpm
        self.activeMinutes = activeMinutes
        self.newWordsCount = newWordsCount
        self.newWords = newWords
    }
}
