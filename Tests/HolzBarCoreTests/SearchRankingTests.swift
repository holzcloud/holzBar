import Testing

@testable import HolzBarCore

@Suite("SearchRanking")
struct SearchRankingTests {
    private func rank(_ items: [String], _ query: String, frecency: [String: Double] = [:]) -> [String] {
        SearchRanking.rank(items, query: query, key: { $0 }, frecency: { frecency[$0] ?? 0 })
    }

    @Test("A short name finds the item it stands for")
    func shortName() {
        #expect(rank(["Battery", "Wi-Fi", "Bluetooth"], "bt").first == "Bluetooth")
        #expect(rank(["Battery", "Wi-Fi"], "wlan").first == "Wi-Fi")
        #expect(rank(["Clock", "Battery", "Sound"], "vol").first == "Sound")
    }

    @Test("A short name finds the item under the Mac's other languages")
    func otherLanguage() {
        #expect(rank(["Uhr", "Akku", "Ton"], "bat").first == "Akku")
        #expect(rank(["時計", "バッテリー"], "bat").first == "バッテリー")
    }

    @Test("A name that holds the typed text still finds it without a short name")
    func withoutSynonym() {
        #expect(rank(["Bluetooth", "Battery"], "bat").first == "Battery")
        #expect(rank(["Spotify", "Safari"], "spo").first == "Spotify")
    }

    @Test("Nothing matches an unrelated query")
    func noMatch() {
        #expect(rank(["Battery", "Clock"], "zzzz").isEmpty)
    }

    @Test("An item opened often ranks above an equal match")
    func frecencyBreaksTies() {
        let items = ["Notes", "Notion"]
        #expect(rank(items, "not", frecency: ["Notion": 4]).first == "Notion")
        #expect(rank(items, "not").first == "Notes")
    }

    @Test("A favourite does not outrank a much better match")
    func frecencyIsBounded() {
        let items = ["Safari Technology Preview Updater", "Spotify"]
        // "spot" is a prefix of Spotify; the other can match only scattered, if at all.
        let ranked = rank(items, "spot", frecency: ["Safari Technology Preview Updater": 1000])
        #expect(ranked.first == "Spotify")
    }

    @Test("A match in order ranks above a misspelling whatever the frecency")
    func typoStaysBelow() {
        let ranked = rank(["Bluetoth", "Bluetooth Settings"], "bluetooth", frecency: ["Bluetoth": 1000])
        #expect(ranked.first == "Bluetooth Settings")
    }

    @Test("A direct hit ranks above the same text reached through a short name")
    func directAboveSynonym() {
        #expect(rank(["Wi-Fi", "WLAN"], "wlan").first == "WLAN")
        #expect(rank(["WLAN", "Wi-Fi"], "wlan") == ["WLAN", "Wi-Fi"])
    }

    @Test("An empty query keeps the order unless something was opened from the search")
    func emptyQuery() {
        let items = ["A", "B", "C"]
        #expect(rank(items, "") == items)
        #expect(rank(items, "  ") == items)
        #expect(rank(items, "", frecency: ["C": 2, "B": 1]) == ["C", "B", "A"])
    }

    @Test("Items with equal frecency keep their order")
    func stable() {
        let items = ["A", "B", "C", "D"]
        #expect(SearchRanking.favouritesFirst(items, frecency: { _ in 1 }) == items)
        #expect(SearchRanking.favouritesFirst(items, frecency: { $0 == "D" ? 1 : 0 }) == ["D", "A", "B", "C"])
    }
}
