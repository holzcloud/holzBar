//
//  ShelfContentsTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("The holzBar Shelf's tiles")
struct ShelfContentsTests {
    private func item(_ id: UInt32, _ name: String = "") -> ShelfContents.Item {
        ShelfContents.Item(windowID: id, name: name.isEmpty ? "Item \(id)" : name)
    }

    private func app(_ bundleID: String) -> ShelfContents.ClosedApp {
        ShelfContents.ClosedApp(bundleID: bundleID, name: bundleID)
    }

    private func ids(_ tiles: [ShelfTile]) -> [String] {
        tiles.map(\.id)
    }

    @Test("The hidden Shelf lists the covered items, then the hidden ones")
    func hiddenShelf() {
        var input = ShelfContents.Input()
        input.covered = [item(1)]
        input.hidden = [item(2), item(3)]
        let tiles = ShelfContents.tiles(input)
        #expect(ids(tiles) == ["item-1", "item-2", "item-3"])
        #expect(tiles.map(\.group) == [.visible, .hidden, .hidden])
    }

    @Test("A folded always-hidden group is one tile that counts its items")
    func foldedGroup() {
        var input = ShelfContents.Input()
        input.hidden = [item(2)]
        input.alwaysHidden = [item(10), item(11), item(12)]
        input.foldsAlwaysHidden = true
        let tiles = ShelfContents.tiles(input)
        #expect(ids(tiles) == ["fold", "item-2"])
        #expect(tiles.first?.kind == .fold(count: 3, isOpen: false))
    }

    @Test("An open fold lists its items after itself, before the hidden ones")
    func openFold() {
        var input = ShelfContents.Input()
        input.hidden = [item(2)]
        input.alwaysHidden = [item(10), item(11)]
        input.foldsAlwaysHidden = true
        input.isFoldOpen = true
        let tiles = ShelfContents.tiles(input)
        #expect(ids(tiles) == ["fold", "item-10", "item-11", "item-2"])
        #expect(tiles.first?.kind == .fold(count: 2, isOpen: true))
    }

    @Test("A row puts a divider between the groups, and none at an end")
    func dividers() {
        var input = ShelfContents.Input()
        input.hidden = [item(2)]
        input.alwaysHidden = [item(10)]
        input.foldsAlwaysHidden = true
        input.isFoldOpen = true
        input.showsDividers = true
        #expect(ids(ShelfContents.tiles(input)) == ["fold", "item-10", "divider-2", "item-2"])

        input.hidden = []
        #expect(ids(ShelfContents.tiles(input)) == ["fold", "item-10"])

        input.alwaysHidden = []
        #expect(ids(ShelfContents.tiles(input)).isEmpty)
    }

    @Test("A fold that holds nothing is not drawn")
    func emptyFold() {
        var input = ShelfContents.Input()
        input.hidden = [item(2)]
        input.foldsAlwaysHidden = true
        #expect(ids(ShelfContents.tiles(input)) == ["item-2"])
    }

    @Test("Closed applications count in the fold and are listed when it opens")
    func closedAppsInFold() {
        var input = ShelfContents.Input()
        input.alwaysHidden = [item(10)]
        input.closedAlwaysHidden = [app("org.example.Closed")]
        input.foldsAlwaysHidden = true
        #expect(ShelfContents.tiles(input).first?.kind == .fold(count: 2, isOpen: false))
        input.isFoldOpen = true
        #expect(ids(ShelfContents.tiles(input)) == ["fold", "item-10", "app-org.example.Closed"])
    }

    @Test("Closed applications follow the items, or come first when the row asks for it")
    func closedPlacement() {
        var input = ShelfContents.Input()
        input.hidden = [item(2), item(3)]
        input.closedHidden = [app("org.example.A")]
        #expect(ids(ShelfContents.tiles(input)) == ["item-2", "item-3", "app-org.example.A"])
        input.closedFirst = true
        #expect(ids(ShelfContents.tiles(input)) == ["app-org.example.A", "item-2", "item-3"])
    }

    @Test("The Shelf of the always-hidden section lists its group without a fold")
    func alwaysHiddenShelf() {
        var input = ShelfContents.Input()
        input.alwaysHidden = [item(10), item(11)]
        let tiles = ShelfContents.tiles(input)
        #expect(ids(tiles) == ["item-10", "item-11"])
        #expect(tiles.map(\.group) == [.alwaysHidden, .alwaysHidden])
    }

    @Test("Only items and closed applications are searched, and the keyboard skips dividers")
    func tileRoles() {
        var input = ShelfContents.Input()
        input.hidden = [item(2)]
        input.closedHidden = [app("org.example.A")]
        input.alwaysHidden = [item(10)]
        input.foldsAlwaysHidden = true
        input.isFoldOpen = true
        input.showsDividers = true
        let tiles = ShelfContents.tiles(input)
        #expect(tiles.filter(\.isSearchable).map(\.id) == ["item-10", "item-2", "app-org.example.A"])
        #expect(tiles.filter { !$0.isNavigable }.map(\.id) == ["divider-2"])
    }

    @Test("A tile keeps its identity when its neighbours change")
    func stableIdentity() {
        var input = ShelfContents.Input()
        input.hidden = [item(5)]
        let before = ShelfContents.tiles(input).map(\.id)
        input.hidden = [item(4), item(5)]
        let after = ShelfContents.tiles(input).map(\.id)
        #expect(before == ["item-5"])
        #expect(after.contains("item-5"))
    }
}
