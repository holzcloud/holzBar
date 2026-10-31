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

    private func system(_ number: Int, _ name: String) -> ShelfContents.SystemItem {
        ShelfContents.SystemItem(key: "system-item:\(number)", name: name)
    }

    @Test("Hidden system items close the hidden group, after the application items")
    func systemItemsInTheHiddenGroup() {
        var input = ShelfContents.Input()
        input.hidden = [item(2)]
        input.hiddenSystemItems = [system(0, "Battery"), system(2, "Clock")]
        let tiles = ShelfContents.tiles(input)
        #expect(ids(tiles) == ["item-2", "system-system-item:0", "system-system-item:2"])
        #expect(tiles.map(\.group) == [.hidden, .hidden, .hidden])
        #expect(tiles.map(\.kind) == [
            .item(windowID: 2), .systemItem(key: "system-item:0"), .systemItem(key: "system-item:2"),
        ])
        #expect(tiles.dropFirst().allSatisfy { $0.isNavigable && $0.isSearchable })
        #expect(tiles.map(\.name) == ["Item 2", "Battery", "Clock"])
    }

    @Test("System tiles are the only tiles of a hidden group that has no applications, and none appear without items")
    func systemItemsAlone() {
        var input = ShelfContents.Input()
        #expect(ShelfContents.tiles(input).isEmpty)
        input.hiddenSystemItems = [system(8, "Control Center")]
        #expect(ids(ShelfContents.tiles(input)) == ["system-system-item:8"])
        input.hiddenSystemItems = []
        #expect(ids(ShelfContents.tiles(input)).isEmpty)
    }

    @Test("A divider separates the visible group from the hidden group, system tiles included, as before")
    func systemItemsWithDividers() {
        var input = ShelfContents.Input()
        input.covered = [item(1)]
        input.hiddenSystemItems = [system(2, "Clock")]
        input.showsDividers = true
        #expect(ids(ShelfContents.tiles(input)) == ["item-1", "divider-0", "system-system-item:2"])
    }

    @Test("The always-hidden section's Shelf lists no system tile: its input carries none")
    func noSystemTilesInTheAlwaysHiddenShelf() {
        var hiddenShelf = ShelfContents.Input()
        hiddenShelf.hidden = [item(2)]
        hiddenShelf.hiddenSystemItems = [system(2, "Clock")]
        var alwaysHiddenShelf = ShelfContents.Input()
        alwaysHiddenShelf.alwaysHidden = [item(10)]
        #expect(ids(ShelfContents.tiles(hiddenShelf)).contains("system-system-item:2"))
        #expect(ids(ShelfContents.tiles(alwaysHiddenShelf)) == ["item-10"])
        #expect(ShelfContents.tiles(alwaysHiddenShelf).allSatisfy { tile in
            if case .systemItem = tile.kind { return false }
            return true
        })
    }

    @Test("All four hidden system items are listed in bar order, after the application items and the closed ones")
    func allFourInBarOrder() {
        var input = ShelfContents.Input()
        input.hidden = [item(2)]
        input.closedHidden = [app("org.example.Closed")]
        input.hiddenSystemItems = [system(0, "Battery"), system(6, "Wi-Fi"), system(8, "Control Center"), system(2, "Clock")]
        let expected = [
            "item-2", "app-org.example.Closed",
            "system-system-item:0", "system-system-item:6", "system-system-item:8", "system-system-item:2",
        ]
        #expect(ids(ShelfContents.tiles(input)) == expected)
        // In a row the closed applications come first; the system items still close the group.
        input.closedFirst = true
        #expect(ids(ShelfContents.tiles(input)) == [
            "app-org.example.Closed", "item-2",
            "system-system-item:0", "system-system-item:6", "system-system-item:8", "system-system-item:2",
        ])
    }

    @Test("A system tile is not in the fold: the folded always-hidden group does not hide it")
    func systemTilesOutsideTheFold() {
        var input = ShelfContents.Input()
        input.alwaysHidden = [item(10)]
        input.foldsAlwaysHidden = true
        input.hiddenSystemItems = [system(2, "Clock")]
        #expect(ids(ShelfContents.tiles(input)) == ["fold", "system-system-item:2"])
        input.isFoldOpen = true
        #expect(ids(ShelfContents.tiles(input)) == ["fold", "item-10", "system-system-item:2"])
    }
}
