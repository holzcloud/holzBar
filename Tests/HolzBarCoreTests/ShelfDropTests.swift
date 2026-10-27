//
//  ShelfDropTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("Dropping a tile in the holzBar Shelf")
struct ShelfDropTests {
    private typealias Rect = HolzBarShelfPlacement.Rect
    private typealias Point = HolzBarShelfPlacement.Point

    // A screen 1000 x 800 with the menu bar at the top (y from 776 up) and a Shelf of one row
    // below it: y from 740 to 776, x from 100 to 400. Tiles are 40 wide and 36 high.
    private let screen = Rect(x: 0, y: 0, width: 1000, height: 800)
    private let panel = Rect(x: 100, y: 740, width: 300, height: 36)

    private func tile(_ id: String, _ group: ShelfGroup, at index: Int, role: ShelfDrop.Role = .item) -> ShelfDrop.Tile {
        ShelfDrop.Tile(id: id, group: group, role: role, frame: Rect(x: 100 + Double(index) * 40, y: 740, width: 40, height: 36))
    }

    private var tiles: [ShelfDrop.Tile] {
        [
            tile("fold", .alwaysHidden, at: 0, role: .fold),
            tile("a", .hidden, at: 1),
            tile("b", .hidden, at: 2),
            tile("c", .hidden, at: 3),
            tile("closed", .hidden, at: 4, role: .other),
        ]
    }

    private func outcome(
        x: Double,
        y: Double = 758,
        dragged: String = "a",
        ordersItems: Bool = true,
        axis: ShelfDrop.Axis = .horizontal,
        tiles customTiles: [ShelfDrop.Tile]? = nil
    ) -> ShelfDrop.Outcome {
        let all = customTiles ?? tiles
        return ShelfDrop.outcome(
            pointer: Point(x: x, y: y),
            dragged: all.first { $0.id == dragged } ?? all[1],
            tiles: all,
            panel: panel,
            screen: screen,
            axis: axis,
            ordersItems: ordersItems
        )
    }

    @Test("The left half of another tile is before it and the right half after")
    func halves() {
        // Tile "c" covers x 220...260.
        #expect(outcome(x: 225) == .beside(tile: "c", side: .before))
        #expect(outcome(x: 255) == .beside(tile: "c", side: .after))
    }

    @Test("A tile dropped on itself changes nothing")
    func onItself() {
        // Tile "a" covers x 140...180.
        #expect(outcome(x: 160, dragged: "a") == .none)
    }

    @Test("A drop in a gap beside the last tile lands next to the nearest tile of the row")
    func gap() {
        let spaced = [
            ShelfDrop.Tile(id: "a", group: .hidden, role: .item, frame: Rect(x: 100, y: 740, width: 40, height: 36)),
            ShelfDrop.Tile(id: "b", group: .hidden, role: .item, frame: Rect(x: 150, y: 740, width: 40, height: 36)),
            ShelfDrop.Tile(id: "c", group: .hidden, role: .item, frame: Rect(x: 200, y: 740, width: 40, height: 36)),
        ]
        // 145 is in the gap between a and b; b is 5 away on the right, a is 5 away on the left.
        let inGap = outcome(x: 146, dragged: "c", tiles: spaced)
        #expect(inGap == .beside(tile: "b", side: .before))
        // 390 is beyond the last tile but inside the panel.
        let beside = outcome(x: 390, dragged: "a", tiles: spaced)
        #expect(beside == .beside(tile: "c", side: .after))
    }

    @Test("The fold tile takes the item into the always-hidden section")
    func foldTile() {
        #expect(outcome(x: 120) == .section(.alwaysHidden))
        #expect(outcome(x: 120, ordersItems: false) == .section(.alwaysHidden))
    }

    @Test("An item dragged from the always-hidden group is not dropped on the fold")
    func foldFromOwnGroup() {
        let open = [
            tile("fold", .alwaysHidden, at: 0, role: .fold),
            tile("x", .alwaysHidden, at: 1),
            tile("a", .hidden, at: 2),
        ]
        #expect(outcome(x: 120, dragged: "x", tiles: open) == .none)
        // A tile of the other group moves into its section on macOS 27 and next to it before.
        #expect(outcome(x: 190, dragged: "x", ordersItems: false, tiles: open) == .section(.hidden))
        #expect(outcome(x: 190, dragged: "x", tiles: open) == .beside(tile: "a", side: .before))
    }

    @Test("Where macOS orders the items a drop in the own section changes nothing")
    func macOS27OwnSection() {
        #expect(outcome(x: 225, ordersItems: false) == .none)
    }

    @Test("A closed application, a divider and a covered item take no drop")
    func nothingToDropOn() {
        // The closed application is at x 260...300.
        #expect(outcome(x: 280) == .none)
        let covered = [
            tile("a", .hidden, at: 0),
            tile("cover", .visible, at: 1),
        ]
        #expect(outcome(x: 145, dragged: "a", tiles: covered) == .none)
    }

    @Test("Above the Shelf is the menu bar")
    func menuBar() {
        #expect(outcome(x: 500, y: 790) == .menuBar)
        #expect(outcome(x: 220, y: 777) == .menuBar)
    }

    @Test("Beside or below the Shelf, or off the screen, is nothing")
    func outside() {
        #expect(outcome(x: 50, y: 758) == .none)
        #expect(outcome(x: 220, y: 700) == .none)
        #expect(outcome(x: 220, y: 900) == .none)
        #expect(outcome(x: -5, y: 790) == .none)
    }

    @Test("Only an item can be dragged, and not a covered one")
    func draggable() {
        #expect(outcome(x: 500, y: 790, dragged: "fold") == .none)
        #expect(outcome(x: 500, y: 790, dragged: "closed") == .none)
        let covered = [tile("cover", .visible, at: 0), tile("a", .hidden, at: 1)]
        #expect(outcome(x: 500, y: 790, dragged: "cover", tiles: covered) == .none)
    }

    @Test("In a column the half nearer the top is before")
    func column() {
        let column = [
            ShelfDrop.Tile(id: "a", group: .hidden, role: .item, frame: Rect(x: 100, y: 700, width: 40, height: 36)),
            ShelfDrop.Tile(id: "b", group: .hidden, role: .item, frame: Rect(x: 100, y: 664, width: 40, height: 36)),
        ]
        let tall = Rect(x: 100, y: 600, width: 40, height: 140)
        func columnOutcome(y: Double) -> ShelfDrop.Outcome {
            ShelfDrop.outcome(
                pointer: Point(x: 120, y: y),
                dragged: column[0],
                tiles: column,
                panel: tall,
                screen: screen,
                axis: .vertical,
                ordersItems: true
            )
        }
        // Tile "b" covers y 664...700; its upper half is above y 682.
        #expect(columnOutcome(y: 690) == .beside(tile: "b", side: .before))
        #expect(columnOutcome(y: 670) == .beside(tile: "b", side: .after))
    }

    @Test("A frame or pointer that is not finite gives nothing")
    func notFinite() {
        #expect(outcome(x: .nan) == .none)
        let broken = [
            tile("a", .hidden, at: 0),
            ShelfDrop.Tile(id: "b", group: .hidden, role: .item, frame: Rect(x: .nan, y: 0, width: 1, height: 1)),
        ]
        #expect(outcome(x: 150, dragged: "a", tiles: broken) == .none)
    }
}
