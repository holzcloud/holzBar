//
//  ShelfFindTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("Typing to find an item in the holzBar Shelf")
struct ShelfFindTests {
    @Test("Typed characters make the query, and the last one can be deleted")
    func typeAndDelete() {
        var find = ShelfFind()
        #expect(!find.isActive)
        let first = find.type("wi")
        let second = find.type("f")
        #expect(first)
        #expect(second)
        #expect(find.query == "wif")
        #expect(find.isActive)
        let deleted = find.deleteLast()
        #expect(deleted)
        #expect(find.query == "wi")
        find.clear()
        #expect(!find.isActive)
        let deletedFromEmpty = find.deleteLast()
        #expect(!deletedFromEmpty)
    }

    @Test("Spaces, controls and the arrows' private-use characters are not typed")
    func notTypable() {
        var find = ShelfFind()
        let results = [" ", "\r", "\u{1B}", "\u{7F}", "\u{F700}", "\u{F703}"].map { find.type($0) }
        #expect(results == [false, false, false, false, false, false])
        #expect(find.query.isEmpty)
        let typed = find.type("a b")
        #expect(typed)
        #expect(find.query == "ab")
    }

    @Test("Letters with accents and other scripts are typed")
    func accents() {
        var find = ShelfFind()
        let results = ["é", "ß", "日"].map { find.type($0) }
        #expect(results == [true, true, true])
        #expect(find.query == "éß日")
    }

    @Test("The query has a limit")
    func limit() {
        var find = ShelfFind()
        let typed = find.type(String(repeating: "a", count: ShelfFind.maximumLength + 10))
        #expect(typed)
        #expect(find.query.count == ShelfFind.maximumLength)
        let more = find.type("b")
        #expect(!more)
    }

    @Test("Stepping goes to the next and the previous match and stops at the ends")
    func stepping() {
        let matches = ["a", "b", "c"]
        #expect(ShelfFind.step(from: "a", by: 1, in: matches) == "b")
        #expect(ShelfFind.step(from: "b", by: 1, in: matches) == "c")
        #expect(ShelfFind.step(from: "c", by: 1, in: matches) == "c")
        #expect(ShelfFind.step(from: "a", by: -1, in: matches) == "a")
        #expect(ShelfFind.step(from: "c", by: -1, in: matches) == "b")
    }

    @Test("Stepping from outside the matches lands on the best one, and with none it stays")
    func steppingFromOutside() {
        #expect(ShelfFind.step(from: "x", by: 1, in: ["a", "b"]) == "a")
        #expect(ShelfFind.step(from: nil, by: -1, in: ["a", "b"]) == "a")
        #expect(ShelfFind.step(from: "x", by: 1, in: []) == "x")
        #expect(ShelfFind.step(from: nil, by: 1, in: []) == nil)
    }

    @Test("A system item's tile is found by its name, and the other tiles do not match")
    func findsSystemTiles() {
        var input = ShelfContents.Input()
        input.hidden = [ShelfContents.Item(windowID: 1, name: "Dropbox")]
        input.hiddenSystemItems = [
            ShelfContents.SystemItem(key: "system-item:0", name: "Battery"),
            ShelfContents.SystemItem(key: "system-item:6", name: "Wi-Fi"),
            ShelfContents.SystemItem(key: "system-item:8", name: "Control Center"),
            ShelfContents.SystemItem(key: "system-item:2", name: "Clock"),
        ]
        let tiles = ShelfContents.tiles(input)
        var find = ShelfFind()
        _ = find.type("wi")
        #expect(find.matches(in: tiles) == ["system-system-item:6"])
        find.clear()
        _ = find.type("clock")
        #expect(find.matches(in: tiles) == ["system-system-item:2"])
        find.clear()
        _ = find.type("zzz")
        #expect(find.matches(in: tiles).isEmpty)
    }
}
