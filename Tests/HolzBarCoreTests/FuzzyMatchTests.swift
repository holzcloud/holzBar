import Foundation
import Testing
@testable import HolzBarCore

@Suite("FuzzyMatch")
struct FuzzyMatchTests {
    @Test("A query whose letters are missing has no score")
    func missingLettersHaveNoScore() {
        #expect(FuzzyMatch.score(query: "xyz", in: "Control Centre") == nil)
        #expect(FuzzyMatch.score(query: "ba", in: "ab") == nil)
        #expect(FuzzyMatch.score(query: "abcd", in: "abc") == nil)
        #expect(FuzzyMatch.score(query: "", in: "abc") == nil)
    }

    @Test("A match at word starts ranks above one inside a word")
    func wordStartsRankHigher() {
        let ranked = FuzzyMatch.rank(["accent", "Control Centre"], query: "cc") { $0 }
        #expect(ranked == ["Control Centre", "accent"])
    }

    @Test("A camel-case match ranks above a scattered one")
    func camelCaseRanksHigher() throws {
        let camelCase = try #require(FuzzyMatch.score(query: "ic", in: "iCloud"))
        let scattered = try #require(FuzzyMatch.score(query: "ic", in: "Music"))
        #expect(camelCase > scattered)
    }

    @Test("A prefix ranks above a match in the middle")
    func prefixRanksHigher() {
        let ranked = FuzzyMatch.rank(["Falcon", "Control"], query: "con") { $0 }
        #expect(ranked == ["Control", "Falcon"])
    }

    @Test("Consecutive letters rank above scattered ones")
    func consecutiveRanksHigher() throws {
        let consecutive = try #require(FuzzyMatch.score(query: "abc", in: "abcxyz"))
        let scattered = try #require(FuzzyMatch.score(query: "abc", in: "axbxcx"))
        #expect(consecutive > scattered)
    }

    @Test("An exact match ranks first")
    func exactMatchRanksFirst() {
        let ranked = FuzzyMatch.rank(
            ["Safari Technology Preview", "Safari Extension", "Safari"],
            query: "safari"
        ) { $0 }
        #expect(ranked.first == "Safari")
    }

    @Test("Case and diacritics are ignored")
    func caseAndDiacriticsAreIgnored() {
        #expect(FuzzyMatch.score(query: "CAFE", in: "café") != nil)
        #expect(FuzzyMatch.score(query: "cafe", in: "Café") == FuzzyMatch.score(query: "cafe", in: "Cafe"))
        #expect(FuzzyMatch.score(query: "écran", in: "Ecran") != nil)
    }

    @Test("Spaces in the query are ignored")
    func spacesInTheQueryAreIgnored() {
        #expect(FuzzyMatch.score(query: "control centre", in: "Control Centre") != nil)
        #expect(FuzzyMatch.score(query: "wi fi", in: "Wi-Fi") != nil)
    }

    @Test("Items with equal scores keep their order")
    func tiesKeepTheirOrder() {
        let items = [(1, "Clock"), (2, "Clock"), (3, "Clock"), (4, "Battery")]
        let ranked = FuzzyMatch.rank(items, query: "clock") { $0.1 }
        #expect(ranked.map(\.0) == [1, 2, 3])
    }

    @Test("An empty query keeps every item in its order")
    func emptyQueryKeepsTheOrder() {
        let items = ["Wi-Fi", "Battery", "Clock"]
        #expect(FuzzyMatch.rank(items, query: "") { $0 } == items)
        #expect(FuzzyMatch.rank(items, query: "  ") { $0 } == items)
    }

    // MARK: Typos

    @Test("A misspelt name finds Spotify")
    func spotfyFindsSpotify() {
        #expect(FuzzyMatch.typoEdits(query: "spotfy", in: "Spotify") == 1)
        #expect(FuzzyMatch.rank(["Music", "Spotify"], query: "spotfy") { $0 } == ["Spotify"])
        #expect(FuzzyMatch.rank(["Music", "Spotlight"], query: "spotlihgt") { $0 } == ["Spotlight"])
    }

    @Test("A misspelt name finds Bluetooth")
    func blutoothFindsBluetooth() {
        #expect(FuzzyMatch.typoEdits(query: "blutooth", in: "Bluetooth") == 1)
        #expect(FuzzyMatch.rank(["Battery", "Bluetooth"], query: "blutooth") { $0 } == ["Bluetooth"])
    }

    @Test("A query of three letters does not match with a typo")
    func shortQueryHasNoTypoMatch() {
        #expect(FuzzyMatch.typoEdits(query: "wfi", in: "wfo") == nil)
        #expect(FuzzyMatch.rank(["wfo"], query: "wfi") { $0 }.isEmpty)
        #expect(FuzzyMatch.allowedEdits(forQueryLength: 3) == 0)
        #expect(FuzzyMatch.allowedEdits(forQueryLength: 4) == 1)
        #expect(FuzzyMatch.allowedEdits(forQueryLength: 7) == 1)
        #expect(FuzzyMatch.allowedEdits(forQueryLength: 8) == 2)
    }

    @Test("An in-order match ranks above a typo match")
    func inOrderRanksAboveTypo() {
        // "contorl" is one swap away from "Control", but its letters appear in order only
        // in "Contoso Remote Launcher".
        #expect(FuzzyMatch.score(query: "contorl", in: "Control Centre") == nil)
        let ranked = FuzzyMatch.rank(["Control Centre", "Contoso Remote Launcher"], query: "contorl") { $0 }
        #expect(ranked == ["Contoso Remote Launcher", "Control Centre"])
    }

    @Test("Swapped neighbours find Control Centre")
    func transpositionFindsControlCentre() {
        #expect(FuzzyMatch.typoEdits(query: "contorl", in: "Control Centre") == 1)
        #expect(FuzzyMatch.typoEdits(query: "cnetre", in: "Control Centre") == 1)
    }

    @Test("A query too many edits away does not match")
    func tooManyEditsDoNotMatch() {
        #expect(FuzzyMatch.typoEdits(query: "sputfa", in: "Spotify") == nil)
        #expect(FuzzyMatch.typoEdits(query: "xxxx", in: "Spotify") == nil)
        #expect(FuzzyMatch.typoEdits(query: "CAFFE", in: "Café") == 1)
    }
}
