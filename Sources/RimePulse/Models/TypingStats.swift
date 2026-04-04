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
    let peakCpm: Int
    let activeMinutes: Double
    let newWordsCount: Int
    let newWords: [String]

    enum CodingKeys: String, CodingKey {
        case date
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case chars
        case charsCjk = "chars_cjk"
        case charsAscii = "chars_ascii"
        case commits
        case avgWordLength = "avg_word_length"
        case charsPerMinute = "chars_per_minute"
        case peakCpm = "peak_cpm"
        case activeMinutes = "active_minutes"
        case newWordsCount = "new_words_count"
        case newWords = "new_words"
    }
}
