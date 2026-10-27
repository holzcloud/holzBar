//
//  ShelfFindRankingTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("Ranking the tiles of the holzBar Shelf")
struct ShelfFindRankingTests {
    private func tiles() -> [ShelfTile] {
        var input = ShelfContents.Input()
        input.hidden = [
            ShelfContents.Item(windowID: 1, name: "Control Centre"),
            ShelfContents.Item(windowID: 2, name: "Dropbox"),
            ShelfContents.Item(windowID: 3, name: "Wi-Fi"),
        ]
        input.closedHidden = [ShelfContents.ClosedApp(bundleID: "org.example.Dock", name: "Dockside")]
        input.alwaysHidden = [ShelfContents.Item(windowID: 9, name: "Bluetooth")]
        input.foldsAlwaysHidden = true
        input.isFoldOpen = true
        return ShelfContents.tiles(input)
    }

    @Test("Nothing matches while nothing is typed")
    func emptyQuery() {
        #expect(ShelfFind().matches(in: tiles()).isEmpty)
    }

    @Test("The best match comes first")
    func bestFirst() {
        var find = ShelfFind()
        find.type("wifi")
        #expect(find.matches(in: tiles()).first == "item-3")
    }

    @Test("Items of a folded group, closed applications and the fold itself")
    func scope() {
        var find = ShelfFind()
        find.type("blue")
        #expect(find.matches(in: tiles()) == ["item-9"])
        find.clear()
        find.type("dock")
        #expect(find.matches(in: tiles()).contains("app-org.example.Dock"))
        #expect(!find.matches(in: tiles()).contains("fold"))
    }

    @Test("A query nothing matches finds nothing")
    func noMatch() {
        var find = ShelfFind()
        find.type("zzzz")
        #expect(find.matches(in: tiles()).isEmpty)
    }
}
