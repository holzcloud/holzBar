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

    @Test("The built-in mood's tints are the design's elevated grounds and its border the increased stroke")
    func builtInTints() {
        #expect(BuiltInMood.lightTint == DesignTokens.Light.groundElevated)
        #expect(BuiltInMood.darkTint == DesignTokens.Dark.groundElevated)
        #expect(BuiltInMood.lightBorder == DesignTokens.IncreasedContrast.Light.stroke)
        #expect(BuiltInMood.darkBorder == DesignTokens.IncreasedContrast.Dark.stroke)
        #expect(BuiltInMood.lightBorder.alpha == 0.5)
        #expect(BuiltInMood.darkBorder.alpha == 0.5)
        #expect(BuiltInMood.borderWidth == 1)
        #expect(BuiltInMood.readableMenuBarID == "holzbar.readable-menu-bar")
    }

    @Test("The built-in mood's identifier and label cannot be taken by a saved look, whatever their case")
    func reservedNames() {
        let reserved = BuiltInMood.reservedNames(label: "Readable menu bar")
        #expect(MoodNaming.unique("Readable menu bar", among: [], reserved: reserved) == "Readable menu bar 2")
        #expect(MoodNaming.unique("readable MENU bar", among: [], reserved: reserved) == "readable MENU bar 2")
        #expect(MoodNaming.unique(BuiltInMood.readableMenuBarID, among: [], reserved: reserved) == BuiltInMood.readableMenuBarID + " 2")
        #expect(MoodNaming.unique("Evening", among: [], reserved: reserved) == "Evening")
        // The English label stays refused where the label is shown in another language.
        let german = BuiltInMood.reservedNames(label: "Gut lesbare Menüleiste")
        #expect(MoodNaming.unique("Readable menu bar", among: [], reserved: german) == "Readable menu bar 2")
        #expect(MoodNaming.unique("Gut lesbare Menüleiste", among: [], reserved: german) == "Gut lesbare Menüleiste 2")
        // A number is skipped when it is taken too.
        #expect(MoodNaming.unique("Readable menu bar", among: ["Readable menu bar 2"], reserved: reserved) == "Readable menu bar 3")
    }

    @Test("The mood limit and a plain name are unchanged")
    func limitUnchanged() {
        #expect(MoodNaming.maximumCount == 12)
        #expect(MoodNaming.unique("Day", among: ["Night"]) == "Day")
    }
}
