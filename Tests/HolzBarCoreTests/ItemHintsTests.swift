import Testing
@testable import HolzBarCore

@Suite("ItemHints")
struct ItemHintsTests {
    @Test("Letters are unique and stable")
    func lettersAreUniqueAndStable() {
        #expect(ItemHints.letters(count: 3) == ["a", "s", "d"])
        #expect(ItemHints.letters(count: 9) == ["a", "s", "d", "f", "j", "k", "l", "g", "h"])
        #expect(ItemHints.letters(count: 0).isEmpty)
        #expect(ItemHints.letters(count: 26).allSatisfy { $0.count == 1 })
        #expect(Set(ItemHints.letters(count: 26)).count == 26)

        let thirty = ItemHints.letters(count: 30)
        #expect(thirty.count == 30)
        #expect(Set(thirty).count == 30)
        // Two letters only after the single ones run out.
        let firstDouble = thirty.firstIndex { $0.count == 2 }
        #expect(firstDouble == 25)
        #expect(thirty[25...].allSatisfy { $0.count == 2 })
        #expect(ItemHints.letters(count: 30) == thirty)
    }

    @Test("No hint is the start of another")
    func noHintIsAPrefixOfAnother() {
        for count in [27, 30, 60, 200, 676] {
            let hints = ItemHints.letters(count: count)
            #expect(hints.count == count)
            #expect(Set(hints).count == count)
            for hint in hints {
                #expect(!hints.contains { $0 != hint && $0.hasPrefix(hint) })
            }
        }
        #expect(ItemHints.letters(count: 1000).count == 676)
    }

    @Test("Typing narrows and picks")
    func typingNarrowsAndPicks() {
        let three = ItemHints.letters(count: 3)
        #expect(ItemHints.match(typed: "a", hints: three) == .item(0))
        #expect(ItemHints.match(typed: "D", hints: three) == .item(2))
        #expect(ItemHints.match(typed: "q", hints: three) == .none)

        let thirty = ItemHints.letters(count: 30)
        let prefix = String(thirty[25].prefix(1))
        #expect(ItemHints.match(typed: prefix, hints: thirty) == .pending)
        #expect(ItemHints.match(typed: thirty[26], hints: thirty) == .item(26))
        #expect(ItemHints.match(typed: "1", hints: thirty) == .none)
    }
}
