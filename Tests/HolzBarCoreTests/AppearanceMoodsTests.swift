//
//  AppearanceMoodsTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("Mood names")
struct AppearanceMoodsTests {
    @Test("A name is trimmed, cleaned and cut")
    func cleaning() {
        let plain = MoodNaming.cleaned("  Night  ")
        let controls = MoodNaming.cleaned("Ni\u{0007}ght\u{202E}")
        let empty = MoodNaming.cleaned(" \n ")
        let long = MoodNaming.cleaned(String(repeating: "a", count: 100))
        #expect(plain == "Night")
        #expect(controls == "Night")
        #expect(empty == nil)
        #expect(long?.count == MoodNaming.maximumNameLength)
    }

    @Test("A name that is taken gets a number, whatever its case")
    func uniqueness() {
        let free = MoodNaming.unique("Day", among: ["Night"])
        let second = MoodNaming.unique("night", among: ["Night"])
        let third = MoodNaming.unique("Night", among: ["Night", "Night 2"])
        #expect(free == "Day")
        #expect(second == "night 2")
        #expect(third == "Night 3")
    }

    @Test("A long name still fits with its number")
    func longUnique() {
        let name = String(repeating: "a", count: MoodNaming.maximumNameLength)
        let result = MoodNaming.unique(name, among: [name])
        #expect(result.count == MoodNaming.maximumNameLength)
        #expect(result.hasSuffix(" 2"))
    }
}
