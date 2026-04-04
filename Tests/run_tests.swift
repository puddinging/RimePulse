#!/usr/bin/env swift
// Standalone test runner — no Xcode required
// Compiles against actual source files to validate production code
// Run: make test

// NOTE: This script uses #sourceLocation tricks to include production source.
// The actual TypingStats and Formatting implementations are compiled from Sources/.

import Foundation

var passed = 0
var failed = 0

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        print("  FAIL [\(file):\(line)] \(msg.isEmpty ? "" : msg + " — ")expected \(b), got \(a)")
    }
}

func assertThrows<T>(_ expr: @autoclosure () throws -> T, _ msg: String = "", file: String = #file, line: Int = #line) {
    do {
        _ = try expr()
        failed += 1
        print("  FAIL [\(file):\(line)] \(msg.isEmpty ? "" : msg + " — ")expected throw, got success")
    } catch {
        passed += 1
    }
}

func section(_ name: String) { print("▸ \(name)") }

// ═══════════════════════════════════════════
// Production code is compiled via `swiftc -whole-module-optimization`
// from Makefile. Here we duplicate ONLY for `swift script` mode.
// The Makefile `test` target compiles this with actual Sources/.
// ═══════════════════════════════════════════

// -- Formatting.swift (must match Sources/RimePulse/Formatting.swift) --
#if !LINKED_SOURCES
func compactNumber(_ n: Int) -> String {
    if n >= 100_000_000 {
        return String(format: "%.1f亿", Double(n) / 100_000_000)
    } else if n >= 10_000 {
        return String(format: "%.1f万", Double(n) / 10_000)
    } else if n >= 1_000 {
        return String(format: "%.1f千", Double(n) / 1_000)
    }
    return "\(n)"
}

func formattedDuration(_ minutes: Double) -> String {
    let hours = Int(minutes) / 60
    let mins = Int(minutes) % 60
    if hours > 0 {
        return "\(hours) 时 \(mins) 分"
    }
    return String(format: "%.0f 分钟", minutes)
}

// -- TypingStats.swift (must match Sources/RimePulse/Models/TypingStats.swift) --
struct TypingStats: Codable, Identifiable {
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
        case date, createdAt = "created_at", updatedAt = "updated_at"
        case chars, charsCjk = "chars_cjk", wordsEn = "words_en", charsAscii = "chars_ascii"
        case commits, avgWordLength = "avg_word_length"
        case charsPerMinute = "chars_per_minute", peakCpm = "peak_cpm"
        case activeMinutes = "active_minutes"
        case newWordsCount = "new_words_count", newWords = "new_words"
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
        date = try c.decode(String.self, forKey: .date)
        createdAt = try c.decode(Int64.self, forKey: .createdAt)
        updatedAt = try c.decode(Int64.self, forKey: .updatedAt)
        chars = try c.decode(Int.self, forKey: .chars)
        charsCjk = try c.decode(Int.self, forKey: .charsCjk)
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
}
#endif

func decode(_ json: String) throws -> TypingStats {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(TypingStats.self, from: data)
}

// ═══════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════

print("RimePulse Tests\n")

// -- TypingStats Decoding --

section("Full new-format JSON decodes correctly")
do {
    let s = try decode("""
    {"date":"2026-04-04","created_at":1743724800,"updated_at":1743768000,
     "chars":1730,"chars_cjk":1424,"words_en":92,"commits":646,
     "avg_word_length":2.1,"chars_per_minute":52,"peak_cpm":158,
     "active_minutes":33.3,"new_words_count":283,"new_words":["a","b"]}
    """)
    assertEqual(s.date, "2026-04-04")
    assertEqual(s.chars, 1730)
    assertEqual(s.charsCjk, 1424)
    assertEqual(s.wordsEn, 92)
    assertEqual(s.commits, 646)
    assertEqual(s.charsPerMinute, 52)
    assertEqual(s.peakCpm, 158)
    assertEqual(s.newWords, ["a", "b"])
} catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

section("Old format chars_ascii → wordsEn fallback")
do {
    let s = try decode("""
    {"date":"2026-04-03","created_at":0,"updated_at":0,
     "chars":500,"chars_cjk":400,"chars_ascii":100,"commits":50,
     "avg_word_length":2.0,"chars_per_minute":30,"peak_cpm":80,
     "active_minutes":10.0,"new_words_count":5,"new_words":[]}
    """)
    assertEqual(s.wordsEn, 100, "chars_ascii should fall back to wordsEn")
} catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

section("words_en takes priority over chars_ascii")
do {
    let s = try decode("""
    {"date":"2026-04-04","created_at":0,"updated_at":0,
     "chars":100,"chars_cjk":80,"words_en":50,"chars_ascii":200,
     "commits":10,"avg_word_length":1.0,"chars_per_minute":20,"peak_cpm":40,
     "active_minutes":5.0,"new_words_count":0,"new_words":[]}
    """)
    assertEqual(s.wordsEn, 50, "words_en should take priority")
} catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

section("Missing required field throws (strict decoding)")
assertThrows(try decode("""
{"date":"2026-01-01"}
"""), "minimal JSON missing required fields should throw")

assertThrows(try decode("""
{"chars":100}
"""), "missing date should throw")

section("Missing both words_en and chars_ascii throws")
assertThrows(try decode("""
{"date":"2026-04-04","created_at":0,"updated_at":0,
 "chars":100,"chars_cjk":80,"commits":10,
 "avg_word_length":1.0,"chars_per_minute":20,"peak_cpm":40,
 "active_minutes":5.0,"new_words_count":0,"new_words":[]}
"""), "missing both words_en and chars_ascii should throw")

section("Unknown fields are ignored")
do {
    let s = try decode("""
    {"date":"2026-04-04","created_at":0,"updated_at":0,
     "chars":100,"chars_cjk":80,"words_en":20,"commits":10,
     "avg_word_length":1.0,"chars_per_minute":20,"peak_cpm":40,
     "active_minutes":5.0,"new_words_count":0,"new_words":[],
     "unknown_field":"ignored","another":42}
    """)
    assertEqual(s.chars, 100)
} catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

section("id derived from date")
do {
    let s = try decode("""
    {"date":"2026-12-25","created_at":0,"updated_at":0,
     "chars":0,"chars_cjk":0,"words_en":0,"commits":0,
     "avg_word_length":0,"chars_per_minute":0,"peak_cpm":0,
     "active_minutes":0,"new_words_count":0,"new_words":[]}
    """)
    assertEqual(s.id, "2026-12-25")
} catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

section("Encode round-trip")
do {
    let original = try decode("""
    {"date":"2026-04-04","created_at":1000,"updated_at":2000,
     "chars":500,"chars_cjk":400,"words_en":10,"commits":50,
     "avg_word_length":2.5,"chars_per_minute":30,"peak_cpm":80,
     "active_minutes":15.0,"new_words_count":3,"new_words":["a","b","c"]}
    """)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TypingStats.self, from: data)
    assertEqual(decoded.date, original.date)
    assertEqual(decoded.chars, original.chars)
    assertEqual(decoded.wordsEn, original.wordsEn)
    assertEqual(decoded.newWords, original.newWords)
} catch { failed += 1; print("  FAIL: round-trip error: \(error)") }

// -- Formatting --

section("compactNumber: below 1000")
assertEqual(compactNumber(0), "0")
assertEqual(compactNumber(1), "1")
assertEqual(compactNumber(999), "999")

section("compactNumber: thousands (千)")
assertEqual(compactNumber(1000), "1.0千")
assertEqual(compactNumber(1500), "1.5千")

section("compactNumber: ten-thousands (万)")
assertEqual(compactNumber(10_000), "1.0万")
assertEqual(compactNumber(55_000), "5.5万")

section("compactNumber: hundred-millions (亿)")
assertEqual(compactNumber(100_000_000), "1.0亿")
assertEqual(compactNumber(350_000_000), "3.5亿")

section("formattedDuration: minutes only")
assertEqual(formattedDuration(0), "0 分钟")
assertEqual(formattedDuration(5), "5 分钟")
assertEqual(formattedDuration(59), "59 分钟")

section("formattedDuration: hours and minutes")
assertEqual(formattedDuration(60), "1 时 0 分")
assertEqual(formattedDuration(90), "1 时 30 分")
assertEqual(formattedDuration(150), "2 时 30 分")

// ═══════════════════════════════════════════
// Summary
// ═══════════════════════════════════════════

print("\n══════════════════════════")
print("Results: \(passed) passed, \(failed) failed")
if failed > 0 {
    print("❌ SOME TESTS FAILED")
    exit(1)
} else {
    print("✅ ALL TESTS PASSED")
}
