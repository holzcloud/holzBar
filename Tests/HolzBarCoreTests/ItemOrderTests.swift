import Foundation
import Testing
@testable import HolzBarCore

@Suite("ItemOrder")
struct ItemOrderTests {
    /// Applies the steps the way the app moves items: the key leaves its place and goes after or
    /// before its anchor.
    private func apply(_ steps: [ItemOrder.Step], to order: [String]) -> [String] {
        var result = order
        for step in steps {
            result.removeAll { $0 == step.key }
            switch step.anchor {
            case .after(let anchor):
                let index = result.firstIndex(of: anchor).map { $0 + 1 } ?? result.count
                result.insert(step.key, at: index)
            case .before(let anchor):
                let index = result.firstIndex(of: anchor) ?? 0
                result.insert(step.key, at: index)
            }
        }
        return result
    }

    // MARK: Sanitized

    @Test("Empty, long and repeated keys are dropped")
    func sanitizedDropsInvalidKeys() {
        let long = String(repeating: "a", count: ItemOrder.maximumKeyLength + 1)
        let limit = String(repeating: "b", count: ItemOrder.maximumKeyLength)
        #expect(ItemOrder.sanitized(["a", "", long, "b", "a", limit]) == ["a", "b", limit])
    }

    @Test("The length is counted in UTF-8 bytes")
    func sanitizedCountsBytes() {
        let wide = String(repeating: "é", count: ItemOrder.maximumKeyLength / 2 + 1)
        #expect(wide.count <= ItemOrder.maximumKeyLength)
        #expect(ItemOrder.sanitized([wide, "a"]) == ["a"])
    }

    @Test("At most the maximum number of keys stays")
    func sanitizedCaps() {
        let keys = (0..<(ItemOrder.maximumKeys + 50)).map { "k\($0)" }
        let result = ItemOrder.sanitized(keys)
        #expect(result.count == ItemOrder.maximumKeys)
        #expect(result.first == "k0")
        #expect(result.last == "k\(ItemOrder.maximumKeys - 1)")
    }

    // MARK: Merge

    @Test("A saved key that is not on the bar keeps its place between its neighbours")
    func mergeKeepsAbsentKeys() {
        #expect(ItemOrder.merge(saved: ["a", "b", "c"], current: ["a", "c"]) == ["a", "b", "c"])
        #expect(ItemOrder.merge(saved: ["x", "a"], current: ["a"]) == ["x", "a"])
    }

    @Test("Two absent keys in a row stay in a row after their predecessor")
    func mergeKeepsAbsentRuns() {
        #expect(ItemOrder.merge(saved: ["a", "x", "y", "b"], current: ["a", "b"]) == ["a", "x", "y", "b"])
        #expect(ItemOrder.merge(saved: ["x", "y", "a"], current: ["a"]) == ["x", "y", "a"])
    }

    @Test("The current order wins for the keys on the bar")
    func mergeCurrentOrderWins() {
        #expect(ItemOrder.merge(saved: ["a", "b"], current: ["b", "a"]) == ["b", "a"])
    }

    @Test("A current key the saved order does not know stays in its place")
    func mergeKeepsUnknownCurrentKeys() {
        #expect(ItemOrder.merge(saved: ["a", "b"], current: ["a", "n", "b"]) == ["a", "n", "b"])
        #expect(ItemOrder.merge(saved: [], current: ["a", "b"]) == ["a", "b"])
        #expect(ItemOrder.merge(saved: ["a"], current: []) == ["a"])
    }

    @Test("Past the cap the saved keys that are absent go first, last one first")
    func mergeCapDropsAbsentKeysFirst() {
        let current = (0..<(ItemOrder.maximumKeys - 2)).map { "c\($0)" }
        let saved = ["old1"] + current + ["old2", "old3"]
        let result = ItemOrder.merge(saved: saved, current: current)
        #expect(result.count == ItemOrder.maximumKeys)
        #expect(result.first == "old1")
        #expect(result.contains("old2"))
        #expect(!result.contains("old3"))
        #expect(Set(current).isSubset(of: result))
    }

    @Test("Past the cap with only current keys the rightmost go")
    func mergeCapOfCurrentKeys() {
        let current = (0..<(ItemOrder.maximumKeys + 5)).map { "c\($0)" }
        let result = ItemOrder.merge(saved: ["gone"], current: current)
        #expect(result.count == ItemOrder.maximumKeys)
        #expect(!result.contains("gone"))
        #expect(result.first == "c0")
    }

    @Test("Merge drops invalid and repeated keys")
    func mergeSanitizes() {
        #expect(ItemOrder.merge(saved: ["", "a", "a"], current: ["b", "b"]) == ["a", "b"])
    }

    // MARK: Stable indices

    @Test("Stable indices are one longest increasing subsequence")
    func stableIndices() {
        #expect(ItemOrder.stableIndices(of: [0, 1, 2]).count == 3)
        #expect(ItemOrder.stableIndices(of: [2, 1, 0]).count == 1)
        #expect(ItemOrder.stableIndices(of: []).isEmpty)
        #expect(ItemOrder.stableIndices(of: [1, 0, 2]).count == 2)
        #expect(ItemOrder.stableIndices(of: [3, 4, 0, 1, 2]) == [2, 3, 4])
        #expect(ItemOrder.stableIndices(of: [5]) == [0])
    }

    @Test("The same ranks give the same indices, and they are strictly increasing")
    func stableIndicesDeterministic() {
        let ranks = [4, 2, 7, 1, 5, 3, 6, 0, 9, 8]
        let first = ItemOrder.stableIndices(of: ranks)
        #expect(first == ItemOrder.stableIndices(of: ranks))
        let values = first.sorted().map { ranks[$0] }
        #expect(values == values.sorted())
        #expect(Set(values).count == values.count)
        #expect(first.count == 4)
    }

    // MARK: Plan

    @Test("Nothing moves when the order is right")
    func planOfRightOrderIsEmpty() {
        #expect(ItemOrder.plan(current: ["a", "b", "c"], wanted: ["a", "b", "c"]).isEmpty)
        #expect(ItemOrder.plan(current: [], wanted: ["a"]).isEmpty)
        #expect(ItemOrder.plan(current: ["a"], wanted: []).isEmpty)
    }

    @Test("One displaced item takes one move")
    func planOfOneDisplacedItem() {
        let steps = ItemOrder.plan(current: ["b", "a", "c"], wanted: ["a", "b", "c"])
        #expect(steps.count == 1)
        #expect(apply(steps, to: ["b", "a", "c"]) == ["a", "b", "c"])
        let right = ItemOrder.plan(current: ["a", "c", "b", "d"], wanted: ["a", "b", "c", "d"])
        #expect(right.count == 1)
        #expect(apply(right, to: ["a", "c", "b", "d"]) == ["a", "b", "c", "d"])
    }

    @Test("A reversed list takes one move fewer than its length")
    func planOfReversedList() {
        let steps = ItemOrder.plan(current: ["c", "b", "a"], wanted: ["a", "b", "c"])
        #expect(steps.count == 2)
        #expect(apply(steps, to: ["c", "b", "a"]) == ["a", "b", "c"])
    }

    @Test("A displaced key that is first in wanted goes before the first key that stays")
    func planFirstKeyGetsBeforeAnchor() {
        let steps = ItemOrder.plan(current: ["b", "c", "a"], wanted: ["a", "b", "c"])
        #expect(steps == [ItemOrder.Step(key: "a", anchor: .before("b"))])
        #expect(apply(steps, to: ["b", "c", "a"]) == ["a", "b", "c"])
    }

    @Test("Keys wanted does not know never move and keep their neighbours")
    func planIgnoresUnknownKeys() {
        let current = ["x", "b", "a", "y", "c"]
        let steps = ItemOrder.plan(current: current, wanted: ["a", "b", "c"])
        #expect(!steps.contains { $0.key == "x" || $0.key == "y" })
        let result = apply(steps, to: current)
        #expect(result == ["x", "a", "b", "y", "c"])
    }

    @Test("Keys wanted has but the bar does not are ignored")
    func planIgnoresAbsentKeys() {
        let current = ["c", "a"]
        let steps = ItemOrder.plan(current: current, wanted: ["a", "gone", "b", "c"])
        #expect(!steps.contains { $0.key == "gone" || $0.key == "b" })
        #expect(apply(steps, to: current) == ["a", "c"])
    }

    @Test("Applying the plan gives the wanted order for many shuffles")
    func planAppliedGivesWantedOrder() {
        let wanted = (0..<12).map { "k\($0)" }
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<200 {
            let extras = ["x1", "x2"]
            var current = (wanted + extras).shuffled(using: &generator)
            current.removeAll { _ in Int.random(in: 0..<10, using: &generator) == 0 }
            let steps = ItemOrder.plan(current: current, wanted: wanted)
            let result = apply(steps, to: current)
            let present = Set(current)
            #expect(result.filter { wanted.contains($0) } == wanted.filter { present.contains($0) })
            #expect(Set(result) == present)
            #expect(steps.count < max(1, current.filter { wanted.contains($0) }.count))
        }
    }

    // MARK: Reappeared

    @Test("A saved key that was not there in the previous read has reappeared")
    func reappearedKey() {
        #expect(ItemOrder.reappeared(previous: ["a", "b"], current: ["a", "b", "c"], saved: ["c"]) == ["c"])
    }

    @Test("A key that is new and not saved, or was there before, has not reappeared")
    func notReappeared() {
        #expect(ItemOrder.reappeared(previous: ["a"], current: ["a", "n"], saved: ["a"]).isEmpty)
        #expect(ItemOrder.reappeared(previous: ["a", "b"], current: ["a", "b"], saved: ["a", "b"]).isEmpty)
        #expect(ItemOrder.reappeared(previous: ["a", "b"], current: ["a"], saved: ["a", "b"]).isEmpty)
    }

    @Test("The function has no first-read rule of its own")
    func reappearedWithoutPrevious() {
        #expect(ItemOrder.reappeared(previous: [], current: ["c"], saved: ["c"]) == ["c"])
    }

    // MARK: Settings

    @Test("ItemOrder is an importable string array")
    func itemOrderIsImportable() {
        #expect(Defaults.Key.importableKinds["ItemOrder"] == .stringArray)
        #expect(Defaults.Key.itemOrder.rawValue == "ItemOrder")
        #expect(!Defaults.Key.localOnlyKeys.contains(.itemOrder))
        let result = Defaults.Key.validatedSettings(["ItemOrder": ["a", "b"]], ownBundleIdentifier: "com.holzcloud.holzBar")
        #expect(result.accepted["ItemOrder"] as? [String] == ["a", "b"])
        #expect(result.ignored.isEmpty)
        let wrong = Defaults.Key.validatedSettings(["ItemOrder": "a"], ownBundleIdentifier: "com.holzcloud.holzBar")
        #expect(wrong.accepted["ItemOrder"] == nil)
    }
}

/// A small deterministic generator, so a failing shuffle can be reproduced.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
