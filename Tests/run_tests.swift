#!/usr/bin/env swift
// Standalone test runner — no Xcode/XCTest required
// Run: swift Tests/run_tests.swift

import Foundation

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL [\(file):\(line)] \(msg)")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a == b {
        passed += 1
    } else {
        failed += 1
        print("  FAIL [\(file):\(line)] \(msg.isEmpty ? "" : msg + " — ")expected \(b), got \(a)")
    }
}

func section(_ name: String) { print("▸ \(name)") }

// ═══════════════════════════════════════════
// Inline dependencies (from Sources/)
// ═══════════════════════════════════════════

// -- Formatting.swift --
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

// -- TypingStats.swift (decoder only) --
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
        createdAt = (try? c.decode(Int64.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decode(Int64.self, forKey: .updatedAt)) ?? 0
        chars = (try? c.decode(Int.self, forKey: .chars)) ?? 0
        charsCjk = (try? c.decode(Int.self, forKey: .charsCjk)) ?? 0
        wordsEn = (try? c.decode(Int.self, forKey: .wordsEn))
                  ?? (try? c.decode(Int.self, forKey: .charsAscii))
                  ?? 0
        commits = (try? c.decode(Int.self, forKey: .commits)) ?? 0
        avgWordLength = (try? c.decode(Double.self, forKey: .avgWordLength)) ?? 0
        charsPerMinute = (try? c.decode(Int.self, forKey: .charsPerMinute)) ?? 0
        peakCpm = (try? c.decode(Int.self, forKey: .peakCpm)) ?? 0
        activeMinutes = (try? c.decode(Double.self, forKey: .activeMinutes)) ?? 0
        newWordsCount = (try? c.decode(Int.self, forKey: .newWordsCount)) ?? 0
        newWords = (try? c.decode([String].self, forKey: .newWords)) ?? []
    }
}

func decode(_ json: String) -> TypingStats? {
    guard let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(TypingStats.self, from: data)
}

// ═══════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════

print("RimePulse Tests\n")

// -- TypingStats Decoding --

section("Full new-format JSON")
if let s = decode("""
{"date":"2026-04-04","created_at":1743724800,"updated_at":1743768000,
 "chars":1730,"chars_cjk":1424,"words_en":92,"commits":646,
 "avg_word_length":2.1,"chars_per_minute":52,"peak_cpm":158,
 "active_minutes":33.3,"new_words_count":283,"new_words":["a","b"]}
""") {
    assertEqual(s.date, "2026-04-04")
    assertEqual(s.chars, 1730)
    assertEqual(s.charsCjk, 1424)
    assertEqual(s.wordsEn, 92)
    assertEqual(s.commits, 646)
    assertEqual(s.charsPerMinute, 52)
    assertEqual(s.peakCpm, 158)
    assertEqual(s.newWords, ["a", "b"])
} else { failed += 1; print("  FAIL: decode returned nil") }

section("Old format chars_ascii fallback")
if let s = decode("""
{"date":"2026-04-03","chars_ascii":100}
""") {
    assertEqual(s.wordsEn, 100, "chars_ascii should fall back to wordsEn")
} else { failed += 1; print("  FAIL: decode returned nil") }

section("Minimal JSON with only date")
if let s = decode("""
{"date":"2026-01-01"}
""") {
    assertEqual(s.date, "2026-01-01")
    assertEqual(s.chars, 0)
    assertEqual(s.wordsEn, 0)
    assertEqual(s.commits, 0)
    assertEqual(s.newWords, [String]())
} else { failed += 1; print("  FAIL: decode returned nil") }

section("Unknown fields ignored")
if let s = decode("""
{"date":"2026-04-04","chars":100,"unknown_field":"ignored"}
""") {
    assertEqual(s.chars, 100)
} else { failed += 1; print("  FAIL: decode returned nil") }

section("words_en priority over chars_ascii")
if let s = decode("""
{"date":"2026-04-04","words_en":50,"chars_ascii":200}
""") {
    assertEqual(s.wordsEn, 50, "words_en should take priority")
} else { failed += 1; print("  FAIL: decode returned nil") }

section("id derived from date")
if let s = decode("""
{"date":"2026-12-25"}
""") {
    assertEqual(s.id, "2026-12-25")
} else { failed += 1; print("  FAIL: decode returned nil") }

section("Encode round-trip")
if let original = decode("""
{"date":"2026-04-04","chars":500,"chars_cjk":400,"words_en":10,
 "commits":50,"avg_word_length":2.5,"chars_per_minute":30,
 "peak_cpm":80,"active_minutes":15.0,"new_words_count":3,
 "new_words":["a","b","c"]}
""") {
    if let data = try? JSONEncoder().encode(original),
       let decoded = try? JSONDecoder().decode(TypingStats.self, from: data) {
        assertEqual(decoded.date, original.date)
        assertEqual(decoded.chars, original.chars)
        assertEqual(decoded.wordsEn, original.wordsEn)
        assertEqual(decoded.newWords, original.newWords)
    } else { failed += 1; print("  FAIL: re-encode/decode failed") }
} else { failed += 1; print("  FAIL: initial decode returned nil") }

// -- Formatting --

section("compactNumber: below 1000")
assertEqual(compactNumber(0), "0")
assertEqual(compactNumber(1), "1")
assertEqual(compactNumber(999), "999")

section("compactNumber: thousands")
assertEqual(compactNumber(1000), "1.0千")
assertEqual(compactNumber(1500), "1.5千")

section("compactNumber: 万")
assertEqual(compactNumber(10_000), "1.0万")
assertEqual(compactNumber(55_000), "5.5万")

section("compactNumber: 亿")
assertEqual(compactNumber(100_000_000), "1.0亿")
assertEqual(compactNumber(350_000_000), "3.5亿")

section("formattedDuration: minutes")
assertEqual(formattedDuration(0), "0 分钟")
assertEqual(formattedDuration(5), "5 分钟")
assertEqual(formattedDuration(59), "59 分钟")

section("formattedDuration: hours")
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
