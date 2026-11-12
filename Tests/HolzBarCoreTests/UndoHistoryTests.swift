import Foundation
import Testing
@testable import HolzBarCore

@Suite("Undo history")
struct UndoHistoryTests {
    private struct Entry: Identifiable, Equatable {
        let id: Int
    }

    private func history(_ ids: ClosedRange<Int>, capacity: Int = 20) -> UndoHistory<Entry> {
        var history = UndoHistory<Entry>(capacity: capacity)
        for id in ids {
            history.push(Entry(id: id))
        }
        return history
    }

    private func snapshot(items: [String: Int] = [:], apps: [String: Int] = [:]) -> LayoutSnapshot {
        LayoutSnapshot(date: Date(timeIntervalSince1970: 0), reason: .manual, itemSections: items, applicationSections: apps)
    }

    @Test("The history keeps twenty changes and returns the oldest it drops")
    func capacity() {
        var history = history(1...20)
        #expect(UndoHistory<Entry>.defaultCapacity == 20)
        let dropped = history.push(Entry(id: 21))
        #expect(dropped == [Entry(id: 1)])
        #expect(history.entries.count == 20)
        #expect(history.entries.first == Entry(id: 2))
        #expect(history.newest == Entry(id: 21))
    }

    @Test("The newest change comes out first")
    func popNewest() {
        var history = history(1...3)
        #expect(history.popNewest() == Entry(id: 3))
        #expect(history.newest == Entry(id: 2))
        #expect(history.entries.count == 2)
    }

    @Test("A change can be taken out by its identifier")
    func removeByID() {
        var history = history(1...3)
        #expect(history.remove(id: 2) == Entry(id: 2))
        #expect(history.entries == [Entry(id: 1), Entry(id: 3)])
        #expect(history.remove(id: 9) == nil)
    }

    @Test("Removing everything returns the changes oldest first")
    func removeAll() {
        var history = history(1...3)
        #expect(history.removeAll() == [Entry(id: 1), Entry(id: 2), Entry(id: 3)])
        #expect(history.isEmpty)
        #expect(history.newest == nil)
    }

    @Test("A deleted element goes back to its index, clamped to the list")
    func reinsert() {
        var list = ["a", "c"]
        DeletionUndo.reinsert("b", at: 1, into: &list)
        #expect(list == ["a", "b", "c"])
        var short = ["a"]
        DeletionUndo.reinsert("z", at: 9, into: &short)
        #expect(short == ["a", "z"])
        var front = ["a"]
        DeletionUndo.reinsert("z", at: -3, into: &front)
        #expect(front == ["z", "a"])
    }

    @Test("An arrangement is put back when no item or app is in another section")
    func arrangementRestored() {
        let wanted = snapshot(items: ["x": 0, "y": 1], apps: ["com.a": 2])
        #expect(ArrangementUndo.isRestored(wanted: wanted, now: wanted))
        #expect(!ArrangementUndo.isRestored(wanted: wanted, now: snapshot(items: ["x": 1, "y": 1], apps: ["com.a": 2])))
        #expect(ArrangementUndo.isRestored(wanted: wanted, now: snapshot(items: ["x": 0], apps: ["com.a": 2])))
        #expect(!ArrangementUndo.isRestored(wanted: wanted, now: snapshot(items: ["x": 0, "y": 1], apps: ["com.a": 0])))
    }

    @Test("An app is put back when every one of its items is in the wanted section")
    func appRestored() {
        let together: [(app: String?, section: Int)] = [("com.a", 1), ("com.a", 1), ("com.b", 0), (nil, 2)]
        #expect(ArrangementUndo.isRestored(app: "com.a", wantedSection: 1, sections: together))
        let apart: [(app: String?, section: Int)] = [("com.a", 1), ("com.a", 0)]
        #expect(!ArrangementUndo.isRestored(app: "com.a", wantedSection: 1, sections: apart))
        #expect(ArrangementUndo.isRestored(app: "com.c", wantedSection: 1, sections: together))
    }
}
