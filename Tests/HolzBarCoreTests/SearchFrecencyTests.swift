import Testing

@testable import HolzBarCore

@Suite("SearchFrecency")
struct SearchFrecencyTests {
    @Test("An open today counts one, an open a half-life ago counts half")
    func decay() {
        #expect(SearchFrecency.weight(ageInDays: 0) == 1)
        #expect(abs(SearchFrecency.weight(ageInDays: 7) - 0.5) < 1e-9)
        #expect(abs(SearchFrecency.weight(ageInDays: 14) - 0.25) < 1e-9)
    }

    @Test("A day in the future counts as today")
    func future() {
        #expect(SearchFrecency.weight(ageInDays: -3) == 1)
    }

    @Test("Recent opens outweigh old ones, and more opens outweigh fewer")
    func recencyAndFrequency() {
        let today = 20_000
        let recent = SearchFrecency.score(counts: [today: 1], today: today)
        let old = SearchFrecency.score(counts: [today - 25: 1], today: today)
        #expect(recent > old)
        let often = SearchFrecency.score(counts: [today: 3, today - 1: 2], today: today)
        #expect(often > recent)
    }

    @Test("Nothing stored scores nothing and adds no bonus")
    func empty() {
        #expect(SearchFrecency.score(counts: [:], today: 20_000) == 0)
        #expect(SearchFrecency.bonus(forScore: 0) == 0)
        #expect(SearchFrecency.bonus(forScore: -1) == 0)
    }

    @Test("The bonus grows with the score but stays below the cap")
    func bonus() {
        var previous = 0
        for score in [0.5, 1, 2, 5, 10, 50, 1000] {
            let value = SearchFrecency.bonus(forScore: score)
            #expect(value >= previous)
            #expect(Double(value) <= SearchFrecency.maxBonus)
            previous = value
        }
        #expect(SearchFrecency.bonus(forScore: SearchFrecency.halfBonusAt) == Int((SearchFrecency.maxBonus / 2).rounded()))
    }

    @Test("The counters of the usage store give an item's frecency")
    func fromCounters() {
        var counters = UsageCounters()
        let today = 20_000
        counters.record(key: "a", day: today)
        counters.record(key: "a", day: today)
        counters.record(key: "b", day: today - 14)
        #expect(counters.frecency(of: "a", today: today) == 2)
        #expect(abs(counters.frecency(of: "b", today: today) - 0.25) < 1e-9)
        #expect(counters.frecency(of: "never", today: today) == 0)
    }
}
