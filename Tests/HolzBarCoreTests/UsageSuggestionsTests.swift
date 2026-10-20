//
//  UsageSuggestionsTests.swift
//  holzBar
//

import Foundation
import Testing

@testable import HolzBarCore

@Suite("Usage suggestions")
struct UsageSuggestionsTests {
    @Test("A day number is a calendar day of the Mac")
    func dayNumbers() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .gmt
        let plus2 = TimeZone(secondsFromGMT: 7200) ?? .gmt
        let late = Date(timeIntervalSince1970: 86_400 * 100 + 23 * 3600)
        let first = UsageCounters.dayNumber(for: late, timeZone: utc)
        let second = UsageCounters.dayNumber(for: late, timeZone: plus2)
        #expect(first == 100)
        #expect(second == 101)
    }

    @Test("Opens are counted per item and per day, and old days are dropped")
    func countingAndPruning() {
        var counters = UsageCounters()
        counters.record(key: "a", day: 100)
        counters.record(key: "a", day: 100)
        counters.record(key: "a", day: 60)
        counters.record(key: "b", day: 40)
        let before = counters.summary
        counters.prune(today: 100)
        let after = counters.summary
        let a = counters.clicks(of: "a", inLast: 30, today: 100)
        #expect(before.clicks == 4)
        #expect(after.items == 1)
        #expect(after.clicks == 2)
        #expect(a == 2)
    }

    @Test("The window of days counts today and the days before it only")
    func window() {
        var counters = UsageCounters()
        counters.record(key: "a", day: 86)
        counters.record(key: "a", day: 87)
        counters.record(key: "a", day: 101)
        let last14 = counters.clicks(of: "a", inLast: 14, today: 100)
        #expect(last14 == 1)
    }

    @Test("Nothing is suggested before the counters ran for 14 days")
    func observation() {
        var counters = UsageCounters(startDay: 100)
        counters.record(key: "used", day: 110)
        let early = UsageSuggester.suggestions(from: counters, visibleKeys: ["used", "idle"], excluded: [], today: 113)
        let ready = UsageSuggester.suggestions(from: counters, visibleKeys: ["used", "idle"], excluded: [], today: 114)
        #expect(early.isEmpty)
        #expect(ready == ["idle"])
    }

    @Test("An item that was opened lately, dismissed or excluded is not suggested")
    func exclusions() {
        var counters = UsageCounters(startDay: 100)
        counters.record(key: "recent", day: 120)
        counters.dismissed.insert("kept")
        let keys = ["recent", "kept", "clock", "idle"]
        let result = UsageSuggester.suggestions(from: counters, visibleKeys: keys, excluded: ["clock"], today: 125)
        #expect(result == ["idle"])
    }

    @Test("Without a start nothing is suggested, and forgetting empties everything")
    func forgetting() {
        var counters = UsageCounters()
        let none = UsageSuggester.suggestions(from: counters, visibleKeys: ["a"], excluded: [], today: 500)
        #expect(none.isEmpty)
        counters.record(key: "a", day: 1)
        counters.dismissed.insert("a")
        counters.forgetEverything()
        let empty = counters == UsageCounters()
        #expect(empty)
    }

    @Test("The daily counts run from the oldest day to today")
    func daily() {
        var counters = UsageCounters()
        counters.record(key: "a", day: 100)
        counters.record(key: "a", day: 70)
        let days = counters.dailyCounts(of: "a", today: 100)
        #expect(days.count == 30)
        #expect(days.first == 0)
        #expect(days.last == 1)
        let total = days.reduce(0, +)
        #expect(total == 1)
    }
}
