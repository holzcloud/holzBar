import Foundation
import Testing
@testable import HolzBarCore

@Suite("ItemRuleMemory")
struct ItemRuleMemoryTests {
    private typealias Visibility = ItemVisibility

    /// A memory with the shown section and where holzBar last put the item.
    private func memory(
        shown: Int? = nil,
        at section: Int? = nil,
        hiding isHiding: Bool = false
    ) -> ItemRuleMemory {
        ItemRuleMemory(
            shownSection: shown,
            applied: section.map { ItemRuleMemory.Applied(section: $0, isHiding: isHiding) }
        )
    }

    private func decide(
        _ holds: Bool?,
        hiding: Int = 1,
        actual: Int?,
        _ memory: ItemRuleMemory = ItemRuleMemory()
    ) -> ItemRuleDecision {
        Visibility.decide(holds: holds, hiding: hiding, actual: actual, memory: memory)
    }

    @Test("A condition that cannot be read moves nothing and changes nothing")
    func unknownConditionChangesNothing() {
        let known = memory(shown: 1, at: 2, hiding: true)
        for actual in [nil, 0, 1, 2] as [Int?] {
            let result = decide(nil, hiding: 2, actual: actual, known)
            var expected = known
            expected.wasAbsent = actual == nil
            #expect(result == ItemRuleDecision(moveTo: nil, memory: expected, revert: nil))
        }
    }

    @Test("A new rule that shows an item leaves it where it is and remembers that section")
    func firstLookKeepsShownItem() {
        let result = decide(true, hiding: 2, actual: 1)
        #expect(result.moveTo == nil)
        #expect(result.revert == nil)
        #expect(result.memory == memory(shown: 1, at: 1))
        // An item that is not found is left alone and nothing is remembered but that it was missing.
        let absent = ItemRuleMemory(wasAbsent: true)
        #expect(decide(true, hiding: 2, actual: nil) == ItemRuleDecision(moveTo: nil, memory: absent, revert: nil))
    }

    @Test("A rule that shows an item sitting in its hiding section moves it out, without a notice")
    func firstLookShowsHiddenItem() {
        let result = decide(true, hiding: 1, actual: 1)
        #expect(result.moveTo == 0)
        #expect(result.revert == nil)
        #expect(result.memory == memory(shown: 0, at: 0))
    }

    @Test("A rule that hides an item for the first time moves it and remembers the section it had")
    func hidesAndRemembers() {
        let result = decide(false, hiding: 1, actual: 0)
        #expect(result.moveTo == 1)
        #expect(result.revert == nil)
        #expect(result.memory == memory(shown: 0, at: 1, hiding: true))
    }

    @Test("An item the user put in Hidden returns there and not to the visible bar")
    func returnsToRememberedSection() {
        let hide = decide(false, hiding: 2, actual: 1, memory(shown: 1, at: 1))
        #expect(hide.moveTo == 2)
        #expect(hide.revert == nil)
        #expect(hide.memory == memory(shown: 1, at: 2, hiding: true))
        let show = decide(true, hiding: 2, actual: 2, hide.memory)
        #expect(show.moveTo == 1)
        #expect(show.revert == nil)
        #expect(show.memory == memory(shown: 1, at: 1))
    }

    @Test("An item that is already hidden stays, and the remembered section is untouched")
    func alreadyHiddenStays() {
        let remembered = memory(shown: 1)
        let inHiding = decide(false, hiding: 1, actual: 1, remembered)
        #expect(inHiding.moveTo == nil)
        #expect(inHiding.memory == memory(shown: 1, at: 1, hiding: true))
        let deeper = decide(false, hiding: 1, actual: 2, remembered)
        #expect(deeper.moveTo == nil)
        #expect(deeper.memory == memory(shown: 1, at: 2, hiding: true))
    }

    @Test("A hidden item found in a more visible section than holzBar left it in is put back with a notice")
    func hiddenItemMovedOutIsPutBack() {
        let result = decide(false, hiding: 1, actual: 0, memory(shown: 0, at: 1, hiding: true))
        #expect(result.moveTo == 1)
        #expect(result.revert == ItemRuleRevert(found: 0, putBack: 1))
        #expect(result.memory == memory(shown: 0, at: 1, hiding: true))
    }

    @Test("A move by hand while the rule shows the item is kept")
    func handMoveWhileShownIsKept() {
        let moved = decide(true, hiding: 2, actual: 1, memory(shown: 0, at: 0))
        #expect(moved.moveTo == nil)
        #expect(moved.revert == nil)
        #expect(moved.memory == memory(shown: 1, at: 1))
        let hide = decide(false, hiding: 2, actual: 1, moved.memory)
        #expect(hide.moveTo == 2)
        let show = decide(true, hiding: 2, actual: 2, hide.memory)
        #expect(show.moveTo == 1)
    }

    @Test("A move into the hiding section or deeper while the rule shows the item is put back with a notice")
    func handMoveIntoHidingWhileShownIsPutBack() {
        let intoHiding = decide(true, hiding: 1, actual: 1, memory(shown: 0, at: 0))
        #expect(intoHiding.moveTo == 0)
        #expect(intoHiding.revert == ItemRuleRevert(found: 1, putBack: 0))
        #expect(intoHiding.memory == memory(shown: 0, at: 0))
        let deeper = decide(true, hiding: 1, actual: 2, memory(shown: 0, at: 0))
        #expect(deeper.revert == ItemRuleRevert(found: 2, putBack: 0))
        // It goes back to the remembered section, not to the visible bar.
        let remembered = decide(true, hiding: 2, actual: 2, memory(shown: 1, at: 1))
        #expect(remembered.moveTo == 1)
        #expect(remembered.revert == ItemRuleRevert(found: 2, putBack: 1))
    }

    @Test("When the conditions stop holding, a shown item moved by hand is remembered where it is")
    func flipAcceptsHandMovedShownItem() {
        let result = decide(false, hiding: 2, actual: 1, memory(shown: 0, at: 0))
        #expect(result.moveTo == 2)
        #expect(result.revert == nil)
        #expect(result.memory == memory(shown: 1, at: 2, hiding: true))
    }

    @Test("A hidden item moved deeper by hand stays there")
    func hiddenItemMovedDeeperStays() {
        let result = decide(false, hiding: 1, actual: 2, memory(shown: 0, at: 1, hiding: true))
        #expect(result.moveTo == nil)
        #expect(result.revert == nil)
        #expect(result.memory == memory(shown: 0, at: 2, hiding: true))
    }

    @Test("An item that is not found is never put back, and is judged by what was applied")
    func absentItemIsNeverReverted() {
        let settled = decide(false, hiding: 1, actual: nil, memory(shown: 0, at: 1, hiding: true))
        #expect(settled.moveTo == nil)
        #expect(settled.revert == nil)
        let notApplied = decide(false, hiding: 1, actual: nil)
        #expect(notApplied.moveTo == 1)
        #expect(notApplied.revert == nil)
        let shown = decide(true, hiding: 1, actual: nil, memory(shown: 0, at: 1, hiding: true))
        #expect(shown.moveTo == 0)
        #expect(shown.revert == nil)
        let stays = decide(true, hiding: 1, actual: nil, memory(shown: 0, at: 0))
        #expect(stays.moveTo == nil)
        #expect(stays.revert == nil)
    }

    @Test("Hiding an item that is not found records nothing as applied and asks for the move once")
    func absentItemIsHiddenOnce() {
        let first = decide(false, hiding: 1, actual: nil, memory(shown: 0))
        #expect(first.moveTo == 1)
        #expect(first.memory.applied == nil)
        #expect(first.memory.shownSection == 0)
        let again = decide(false, hiding: 1, actual: nil, first.memory)
        #expect(again.moveTo == nil)
        #expect(again.memory == first.memory)
    }

    @Test("An item that appears in a more visible section than the hiding one is a first look, not a hand move")
    func appearingItemIsAFreshFirstLook() {
        let missing = decide(false, hiding: 1, actual: nil, memory(shown: 0)).memory
        let appeared = decide(false, hiding: 1, actual: 0, missing)
        #expect(appeared.moveTo == 1)
        #expect(appeared.revert == nil)
        #expect(appeared.memory == memory(shown: 0, at: 1, hiding: true))
        // The same holds for an item that was hidden before it went missing.
        let gone = decide(false, hiding: 1, actual: nil, memory(shown: 0, at: 1, hiding: true)).memory
        let back = decide(false, hiding: 1, actual: 0, gone)
        #expect(back.moveTo == 1)
        #expect(back.revert == nil)
        // And for a shown item that comes back in the hiding section.
        let goneShown = decide(true, hiding: 1, actual: nil, memory(shown: 0, at: 0)).memory
        let backHidden = decide(true, hiding: 1, actual: 1, goneShown)
        #expect(backHidden.moveTo == 0)
        #expect(backHidden.revert == nil)
    }

    @Test("A first look at a hidden item keeps the shown section that is stored")
    func firstLookKeepsStoredShownSection() {
        let result = decide(false, hiding: 2, actual: 0, memory(shown: 1))
        #expect(result.moveTo == 2)
        #expect(result.memory == memory(shown: 1, at: 2, hiding: true))
        let show = decide(true, hiding: 2, actual: 2, result.memory)
        #expect(show.moveTo == 1)
        // Nothing stored: the section it is found in is remembered.
        #expect(decide(false, hiding: 2, actual: 0).memory.shownSection == 0)
        // A rule that shows the item adopts the section it is found in.
        #expect(decide(true, hiding: 2, actual: 0, memory(shown: 1)).memory == memory(shown: 0, at: 0))
    }

    @Test("A move that did not reach the item keeps the earlier applied state")
    func settledMemoryKeepsAppliedWhenNotReached() {
        let before = memory(shown: 0, at: 0)
        let decision = decide(false, hiding: 1, actual: 0, before)
        #expect(decision.moveTo == 1)
        #expect(Visibility.settledMemory(of: decision, before: before, reached: true) == decision.memory)
        let notReached = Visibility.settledMemory(of: decision, before: before, reached: false)
        #expect(notReached.applied == before.applied)
        #expect(notReached.shownSection == decision.memory.shownSection)
        // The next look neither announces a hand move nor loses the move.
        let next = decide(false, hiding: 1, actual: 0, notReached)
        #expect(next.moveTo == 1)
        #expect(next.revert == nil)
        // First look: nothing was applied before, so nothing is.
        let fresh = decide(false, hiding: 1, actual: 0)
        #expect(Visibility.settledMemory(of: fresh, before: ItemRuleMemory(), reached: false).applied == nil)
        // A decision without a move is kept as it is.
        let still = decide(false, hiding: 1, actual: 1, memory(shown: 0, at: 1, hiding: true))
        #expect(Visibility.settledMemory(of: still, before: before, reached: false) == still.memory)
    }

    @Test("A revert that did not reach the item is not remembered as put back")
    func unreachedRevertRepeatsWithoutHandMoveState() {
        let before = memory(shown: 0, at: 1, hiding: true)
        let decision = decide(false, hiding: 1, actual: 0, before)
        #expect(decision.revert == ItemRuleRevert(found: 0, putBack: 1))
        let kept = Visibility.settledMemory(of: decision, before: before, reached: false)
        #expect(kept.applied == before.applied)
    }

    @Test("A move is given up after three tries that did not reach the item, until the facts change")
    func movesAreBounded() {
        var attempts = ItemRuleMoveAttempts()
        #expect(!attempts.isGivenUp(key: "a:A", target: 1, isFound: true))
        for _ in 0..<(ItemRuleMoveAttempts.limit - 1) {
            attempts.recordFailure(key: "a:A", target: 1, isFound: true)
            #expect(!attempts.isGivenUp(key: "a:A", target: 1, isFound: true))
        }
        attempts.recordFailure(key: "a:A", target: 1, isFound: true)
        #expect(attempts.isGivenUp(key: "a:A", target: 1, isFound: true))
        // Another target, or the item appearing or going, is another case.
        #expect(!attempts.isGivenUp(key: "a:A", target: 0, isFound: true))
        #expect(!attempts.isGivenUp(key: "a:A", target: 1, isFound: false))
        #expect(!attempts.isGivenUp(key: "b:B", target: 1, isFound: true))
        // A try with other facts starts the count again.
        attempts.recordFailure(key: "a:A", target: 0, isFound: true)
        #expect(!attempts.isGivenUp(key: "a:A", target: 1, isFound: true))
        #expect(!attempts.isGivenUp(key: "a:A", target: 0, isFound: true))
        for _ in 0..<ItemRuleMoveAttempts.limit {
            attempts.recordFailure(key: "a:A", target: 1, isFound: true)
        }
        #expect(attempts.isGivenUp(key: "a:A", target: 1, isFound: true))
        attempts.recordSuccess(key: "a:A")
        #expect(!attempts.isGivenUp(key: "a:A", target: 1, isFound: true))
        for _ in 0..<ItemRuleMoveAttempts.limit {
            attempts.recordFailure(key: "a:A", target: 1, isFound: true)
        }
        attempts.removeAll()
        #expect(attempts == ItemRuleMoveAttempts())
    }

    @Test("A move that was given up is dropped from the decisions and causes no further work")
    func givenUpMovesAreDropped() {
        let memories = ["a:A": memory(shown: 0, at: 0), "b:B": memory(shown: 0, at: 0)]
        let follows: [(itemKey: String, holds: Bool?, hiding: Int)] = [
            (itemKey: "a:A", holds: false, hiding: 1),
            (itemKey: "b:B", holds: false, hiding: 1),
        ]
        let decisions = Visibility.decisions(follows: follows, actual: ["a:A": 0, "b:B": 0], memory: memories)
        var attempts = ItemRuleMoveAttempts()
        for _ in 0..<ItemRuleMoveAttempts.limit {
            attempts.recordFailure(key: "a:A", target: 1, isFound: true)
        }
        let kept = Visibility.droppingGivenUpMoves(from: decisions, memory: memories, attempts: attempts, found: ["a:A", "b:B"])
        #expect(kept["a:A"]?.moveTo == nil)
        #expect(kept["a:A"]?.revert == nil)
        #expect(kept["a:A"]?.memory.applied == memories["a:A"]?.applied)
        #expect(kept["b:B"]?.moveTo == 1)
        // With the dropped decision's memory stored, nothing is left to do.
        let stored = kept["a:A"]?.memory ?? ItemRuleMemory()
        let again = Visibility.decisions(follows: follows, actual: ["a:A": 0, "b:B": 0], memory: ["a:A": stored])
        let dropped = Visibility.droppingGivenUpMoves(from: again, memory: ["a:A": stored], attempts: attempts, found: ["a:A"])
        #expect(dropped["a:A"]?.moveTo == nil)
        #expect(dropped["a:A"]?.memory == stored)
    }

    @Test("Loading the rules again keeps what holzBar knows and refreshes the shown sections")
    func mergingKeepsAppliedMemory() {
        let current = [
            "a:A": memory(shown: 0, at: 1, hiding: true),
            "gone:G": memory(shown: 1, at: 1),
            "c:C": memory(at: 0),
        ]
        let stored = [
            "a:A": ItemRuleMemory(shownSection: 1),
            "b:B": ItemRuleMemory(shownSection: 0),
        ]
        let merged = Visibility.mergingStored(stored, into: current, ruleKeys: ["a:A", "b:B", "c:C"])
        #expect(merged == [
            "a:A": memory(shown: 1, at: 1, hiding: true),
            "b:B": memory(shown: 0),
            "c:C": memory(at: 0),
        ])
        #expect(Visibility.mergingStored([:], into: [:], ruleKeys: ["a:A"]).isEmpty)
        #expect(Visibility.mergingStored(stored, into: current, ruleKeys: []).isEmpty)
        let keys = (0..<(AutomationRule.maximumCount + 5)).map { "app\($0):Item" }
        let many = Dictionary(uniqueKeysWithValues: keys.map { ($0, memory(shown: 1)) })
        #expect(Visibility.mergingStored([:], into: many, ruleKeys: Set(keys)).count == AutomationRule.maximumCount)
    }

    @Test("A hiding section edited to a deeper one moves the item, and the old one is not remembered")
    func editedHidingSectionMovesItem() {
        let result = decide(false, hiding: 2, actual: 1, memory(shown: 0, at: 1, hiding: true))
        #expect(result.moveTo == 2)
        #expect(result.revert == nil)
        #expect(result.memory == memory(shown: 0, at: 2, hiding: true))
        // Shown items follow the edit too: nothing stays in what is now the hiding section.
        let shown = decide(true, hiding: 1, actual: 1, memory(shown: 1, at: 1))
        #expect(shown.moveTo == 0)
        #expect(shown.revert == nil)
    }

    @Test("A remembered section that is not more visible than the hiding section is ignored")
    func unusableRememberedSectionIsIgnored() {
        let result = decide(true, hiding: 1, actual: 1, memory(shown: 1, at: 1, hiding: true))
        #expect(result.moveTo == 0)
        #expect(result.memory == memory(shown: 0, at: 0))
        let negative = decide(true, hiding: 2, actual: 2, memory(shown: -3, at: 2, hiding: true))
        #expect(negative.moveTo == 0)
    }

    @Test("Deciding again with a decision carried out yields no move and no notice")
    func noLoop() {
        let memories: [ItemRuleMemory] = [
            ItemRuleMemory(),
            memory(shown: 0),
            memory(shown: 1),
            memory(shown: 5),
            memory(at: 0),
            memory(at: 1),
            memory(at: 2),
            memory(shown: 0, at: 1, hiding: true),
            memory(shown: 1, at: 2, hiding: true),
            memory(shown: 1, at: 1, hiding: true),
            memory(shown: 0, at: 2, hiding: true),
        ]
        var checked = 0
        for holds in [nil, true, false] as [Bool?] {
            for hiding in [1, 2] {
                for actual in [nil, 0, 1, 2] as [Int?] {
                    for start in memories {
                        let first = decide(holds, hiding: hiding, actual: actual, start)
                        // An item that is not found cannot be moved: it is still missing.
                        let again = decide(
                            holds,
                            hiding: hiding,
                            actual: actual == nil ? nil : first.moveTo ?? actual,
                            first.memory
                        )
                        #expect(again.moveTo == nil, "holds \(String(describing: holds)) hiding \(hiding) actual \(String(describing: actual))")
                        #expect(again.revert == nil)
                        #expect(again.memory == first.memory)
                        checked += 1
                    }
                }
            }
        }
        #expect(checked == 3 * 2 * 4 * memories.count)
    }

    @Test("A revert is always a move, and a move to the hiding section never remembers it as shown")
    func revertsAreMoves() {
        for holds in [true, false] {
            for hiding in [1, 2] {
                for actual in [nil, 0, 1, 2] as [Int?] {
                    let result = decide(holds, hiding: hiding, actual: actual, memory(shown: 0, at: 0))
                    if result.revert != nil {
                        #expect(result.moveTo != nil)
                    }
                    if let shown = result.memory.shownSection {
                        #expect(shown < hiding || shown == 0)
                    }
                }
            }
        }
    }

    @Test("Decisions are made per followed item, with an empty memory for a new one")
    func decisionsPerItem() {
        let follows: [(itemKey: String, holds: Bool?, hiding: Int)] = [
            (itemKey: "a:A", holds: false, hiding: 1),
            (itemKey: "b:B", holds: true, hiding: 2),
            (itemKey: "c:C", holds: nil, hiding: 1),
        ]
        let result = Visibility.decisions(
            follows: follows,
            actual: ["a:A": 0, "b:B": 1, "d:D": 0],
            memory: ["b:B": memory(shown: 0, at: 0)]
        )
        #expect(result.count == 3)
        #expect(result["a:A"]?.moveTo == 1)
        #expect(result["b:B"]?.memory.shownSection == 1)
        #expect(result["c:C"]?.moveTo == nil)
    }

    @Test("Notices keep the newest first, one per item, at most ten")
    func noticesAreBounded() {
        func notice(_ key: String, in section: Int = 1) -> ItemRuleNotice {
            ItemRuleNotice(itemKey: key, itemName: key, putBackIn: section)
        }
        var notices = [ItemRuleNotice]()
        for index in 0..<12 {
            notices = ItemRuleNotices.adding(notice("k\(index)"), to: notices)
        }
        #expect(notices.count == 10)
        #expect(notices.first?.itemKey == "k11")
        #expect(notices.last?.itemKey == "k2")
        let replaced = ItemRuleNotices.adding(notice("k5", in: 2), to: notices)
        #expect(replaced.count == 10)
        #expect(replaced.first == notice("k5", in: 2))
        #expect(replaced.filter { $0.itemKey == "k5" }.count == 1)
        #expect(ItemRuleNotices.adding(notice("x"), to: [notice("y")], limit: 1).map(\.itemKey) == ["x"])
    }

    @Test("Notices of items that are no longer controlled go")
    func noticesFollowTheRules() {
        let notices = [
            ItemRuleNotice(itemKey: "a", itemName: "A", putBackIn: 1),
            ItemRuleNotice(itemKey: "b", itemName: "B", putBackIn: 2),
        ]
        #expect(ItemRuleNotices.keeping(notices, controlled: ["b"]).map(\.itemKey) == ["b"])
        #expect(ItemRuleNotices.keeping(notices, controlled: []).isEmpty)
    }

    @Test("An item name is cleaned, cut to 60 characters and replaced by the fallback when empty")
    func namesAreCleaned() {
        #expect(ItemRuleNotices.cleanedName("  VPN\n\tStatus\u{0007}  ", fallback: "Item") == "VPNStatus")
        #expect(ItemRuleNotices.cleanedName("A\u{2028}B\u{202E}C", fallback: "Item") == "ABC")
        #expect(ItemRuleNotices.cleanedName("\n\t \u{0000}", fallback: "Item") == "Item")
        #expect(ItemRuleNotices.cleanedName("", fallback: "Item") == "Item")
        let long = String(repeating: "x", count: 100)
        let cut = ItemRuleNotices.cleanedName(long, fallback: "Item")
        #expect(cut.count == 60)
        #expect(cut.hasSuffix("…"))
        let exact = String(repeating: "y", count: 60)
        #expect(ItemRuleNotices.cleanedName(exact, fallback: "Item") == exact)
    }

    @Test("Stored sections come back only for item rules, as 0 or 1, at most the rule limit")
    func storedSectionsAreValidated() {
        let stored = ["a:A": 1, "b:B": 0, "c:C": 2, "d:D": -1, "gone:G": 1]
        let restored = Visibility.restoredMemory(from: stored, ruleKeys: ["a:A", "b:B", "c:C", "d:D"])
        #expect(restored == ["a:A": ItemRuleMemory(shownSection: 1), "b:B": ItemRuleMemory(shownSection: 0)])
        #expect(restored.values.allSatisfy { $0.applied == nil })

        let keys = (0..<(AutomationRule.maximumCount + 20)).map { "app\($0):Item" }
        let many = Dictionary(uniqueKeysWithValues: keys.map { ($0, 1) })
        #expect(Visibility.restoredMemory(from: many, ruleKeys: Set(keys)).count == AutomationRule.maximumCount)
        #expect(Visibility.restoredMemory(from: [:], ruleKeys: ["a:A"]).isEmpty)
    }

    @Test("Only known shown sections of item rules are stored")
    func shownSectionsToStore() {
        let remembered = [
            "a:A": memory(shown: 1, at: 2, hiding: true),
            "b:B": memory(at: 1, hiding: true),
            "c:C": memory(shown: 0),
            "gone:G": memory(shown: 1),
            "bad:B": memory(shown: 7),
        ]
        let stored = Visibility.persistableShownSections(remembered, ruleKeys: ["a:A", "b:B", "c:C", "bad:B"])
        #expect(stored == ["a:A": 1, "c:C": 0])
        #expect(Visibility.persistableShownSections([:], ruleKeys: ["a:A"]).isEmpty)
    }

    @Test("What is stored restores to the same shown sections")
    func storedSectionsRoundTrip() {
        let remembered = ["a:A": memory(shown: 1, at: 2, hiding: true), "c:C": memory(shown: 0, at: 0)]
        let keys: Set<String> = ["a:A", "c:C"]
        let restored = Visibility.restoredMemory(
            from: Visibility.persistableShownSections(remembered, ruleKeys: keys),
            ruleKeys: keys
        )
        #expect(restored.mapValues(\.shownSection) == ["a:A": 1, "c:C": 0])
    }

    @Test("The keys of item rules include the rules that are off")
    func ruleKeysIncludeRulesThatAreOff() {
        var off = AutomationRule(
            name: "B",
            clauses: [AutomationClause(condition: .power(.battery))],
            action: .showItemOnlyWhile(itemKey: "b:B", hiding: .hidden)
        )
        off.isEnabled = false
        let zen = AutomationRule(name: "Zen", clauses: [AutomationClause(condition: .power(.battery))], action: .zen(true))
        #expect(Visibility.ruleKeys(in: [off, zen]) == ["b:B"])
    }
}
