// Test runner — compiles against actual production source files
// Run: make test (links Sources/RimePulse/Models/TypingStats.swift & Formatting.swift)

import Foundation

// ═══════════════════════════════════════════
// Test harness
// ═══════════════════════════════════════════

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

func decode(_ json: String) throws -> TypingStats {
    let data = json.data(using: .utf8)!
    return try JSONDecoder().decode(TypingStats.self, from: data)
}

// ═══════════════════════════════════════════
// Entry point
// ═══════════════════════════════════════════

@main
enum TestRunner {
    static func main() {
        print("RimePulse Tests (linked sources)\n")

        // -- TypingStats Decoding --

        section("Full new-format JSON decodes correctly")
        do {
            let s = try decode("""
            {"date":"2026-04-04","created_at":1743724800,"updated_at":1743768000,
             "chars":1730,"chars_cjk":1424,"chars_ascii":92,"commits":646,
             "avg_word_length":2.1,"chars_per_minute":52,"current_cpm":49,"peak_cpm":158,
             "burst_cpm":210,
             "active_minutes":33.3,"new_words_count":283,"new_words":["a","b"]}
            """)
            assertEqual(s.date, "2026-04-04")
            assertEqual(s.chars, 1730)
            assertEqual(s.charsCjk, 1424)
            assertEqual(s.charsAscii, 92)
            assertEqual(s.commits, 646)
            assertEqual(s.charsPerMinute, 52)
            assertEqual(s.currentCpm, 49)
            assertEqual(s.peakCpm, 158)
            assertEqual(s.burstCpm, 210)
            assertEqual(s.newWords, ["a", "b"])
        } catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

        section("Legacy words_en → charsAscii fallback")
        do {
            let s = try decode("""
            {"date":"2026-04-03","created_at":0,"updated_at":0,
             "chars":500,"chars_cjk":400,"words_en":100,"commits":50,
             "avg_word_length":2.0,"chars_per_minute":30,"peak_cpm":80,
             "active_minutes":10.0,"new_words_count":5,"new_words":[]}
            """)
            assertEqual(s.charsAscii, 100, "words_en should fall back to charsAscii")
            assertEqual(s.currentCpm, 30, "missing current_cpm should fall back to chars_per_minute")
            assertEqual(s.burstCpm, 0, "missing burst_cpm should default to 0")
        } catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

        section("chars_ascii takes priority over words_en")
        do {
            let s = try decode("""
            {"date":"2026-04-04","created_at":0,"updated_at":0,
             "chars":100,"chars_cjk":80,"words_en":50,"chars_ascii":200,
             "commits":10,"avg_word_length":1.0,"chars_per_minute":20,"peak_cpm":40,
             "active_minutes":5.0,"new_words_count":0,"new_words":[]}
            """)
            assertEqual(s.charsAscii, 200, "chars_ascii should take priority")
        } catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

        section("Missing required field throws (strict decoding)")
        assertThrows(try decode("""
        {"date":"2026-01-01"}
        """), "minimal JSON missing required fields should throw")

        assertThrows(try decode("""
        {"chars":100}
        """), "missing date should throw")

        section("Missing both chars_ascii and words_en throws")
        assertThrows(try decode("""
        {"date":"2026-04-04","created_at":0,"updated_at":0,
         "chars":100,"chars_cjk":80,"commits":10,
         "avg_word_length":1.0,"chars_per_minute":20,"peak_cpm":40,
         "active_minutes":5.0,"new_words_count":0,"new_words":[]}
        """), "missing both chars_ascii and words_en should throw")

        section("Unknown fields are ignored")
        do {
            let s = try decode("""
            {"date":"2026-04-04","created_at":0,"updated_at":0,
             "chars":100,"chars_cjk":80,"chars_ascii":20,"commits":10,
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
             "chars":0,"chars_cjk":0,"chars_ascii":0,"commits":0,
             "avg_word_length":0,"chars_per_minute":0,"peak_cpm":0,
             "active_minutes":0,"new_words_count":0,"new_words":[]}
            """)
            assertEqual(s.id, "2026-12-25")
        } catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

        section("liveCurrentCpm fallback for non-epoch updated_at")
        do {
            let s = try decode("""
            {"date":"2026-04-12","created_at":0,"updated_at":206178561,
             "chars":100,"chars_cjk":80,"chars_ascii":20,"commits":10,
             "avg_word_length":1.0,"chars_per_minute":20,"current_cpm":77,"peak_cpm":90,
             "active_minutes":5.0,"new_words_count":0,"new_words":[]}
            """)
            assertEqual(s.liveCurrentCpm, 77)
        } catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

        section("liveCurrentCpm stale for old epoch updated_at")
        do {
            let s = try decode("""
            {"date":"2026-04-12","created_at":0,"updated_at":1000000000000,
             "chars":100,"chars_cjk":80,"chars_ascii":20,"commits":10,
             "avg_word_length":1.0,"chars_per_minute":20,"current_cpm":77,"peak_cpm":90,
             "active_minutes":5.0,"new_words_count":0,"new_words":[]}
            """)
            assertEqual(s.liveCurrentCpm, 0)
        } catch { failed += 1; print("  FAIL: unexpected throw: \(error)") }

        section("Encode round-trip")
        do {
            let original = try decode("""
            {"date":"2026-04-04","created_at":1000,"updated_at":2000,
             "chars":500,"chars_cjk":400,"chars_ascii":10,"commits":50,
             "avg_word_length":2.5,"chars_per_minute":30,"peak_cpm":80,"burst_cpm":150,
             "active_minutes":15.0,"new_words_count":3,"new_words":["a","b","c"]}
            """)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(TypingStats.self, from: data)
            assertEqual(decoded.date, original.date)
            assertEqual(decoded.chars, original.chars)
            assertEqual(decoded.charsAscii, original.charsAscii)
            assertEqual(decoded.burstCpm, original.burstCpm)
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

        // -- Summary --

        print("\n══════════════════════════")
        print("Results: \(passed) passed, \(failed) failed")
        if failed > 0 {
            print("❌ SOME TESTS FAILED")
            exit(1)
        } else {
            print("✅ ALL TESTS PASSED")
        }
    }
}
