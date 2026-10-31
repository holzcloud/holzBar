import Testing
@testable import HolzBarCore

@Suite("ReorderDrag")
struct ReorderDragTests {
    typealias Item = ReorderDrag.Item
    typealias Move = ReorderPlan.Move

    // Frames in the range of the real bar: items 16 to 109 points wide, 6 points apart.
    private let a = Item(id: "a", minX: 100, maxX: 120, midY: 12)
    private let b = Item(id: "b", minX: 126, maxX: 160, midY: 12)
    private let c = Item(id: "c", minX: 166, maxX: 190, midY: 12)
    private let d = Item(id: "d", minX: 196, maxX: 230, midY: 12)
    private var row: [Item] { [a, b, c, d] }
    private let all: Set<String> = ["a", "b", "c", "d"]

    @Test("Moving c before a drags c from its centre to one point left of a's left edge")
    func movesLeft() throws {
        let step = try #require(ReorderDrag.step(for: Move(key: "c", before: "a"), in: row, sectionIDs: all, bias: .primary))
        #expect(step.id == "c")
        #expect(step.from == ReorderDrag.Point(x: 178, y: 12))
        #expect(step.to == ReorderDrag.Point(x: 99, y: 12))
        #expect(step.bias == .primary)
    }

    @Test("Moving a to the end drags it to two points right of the last item's right edge")
    func movesToTheEnd() throws {
        let step = try #require(ReorderDrag.step(for: Move(key: "a", before: nil), in: row, sectionIDs: all, bias: .primary))
        #expect(step.from == ReorderDrag.Point(x: 110, y: 12))
        #expect(step.to == ReorderDrag.Point(x: 232, y: 12))
    }

    @Test("Moving a item right to before a later one lands after the item that stands before it")
    func movesRightInTheMiddle() throws {
        // a before d: a lands after c, whose right edge is 190.
        let step = try #require(ReorderDrag.step(for: Move(key: "a", before: "d"), in: row, sectionIDs: all, bias: .primary))
        #expect(step.to == ReorderDrag.Point(x: 192, y: 12))
    }

    @Test("An item that already stands before the other needs no step and is placed")
    func alreadyPlaced() {
        let move = Move(key: "b", before: "c")
        #expect(ReorderDrag.step(for: move, in: row, sectionIDs: all, bias: .primary) == nil)
        #expect(ReorderDrag.isPlaced(move, in: row, sectionIDs: all))
        #expect(ReorderDrag.isPlaced(Move(key: "d", before: nil), in: row, sectionIDs: all))
        #expect(!ReorderDrag.isPlaced(Move(key: "c", before: "a"), in: row, sectionIDs: all))
        // Not directly before is not placed.
        #expect(!ReorderDrag.isPlaced(Move(key: "a", before: "c"), in: row, sectionIDs: all))
    }

    @Test("The alternate bias aims one point past the neighbour's midpoint")
    func alternateBias() throws {
        let left = try #require(ReorderDrag.step(for: Move(key: "c", before: "a"), in: row, sectionIDs: all, bias: .alternate))
        #expect(left.to.x == 109)
        #expect(left.bias == .alternate)
        let end = try #require(ReorderDrag.step(for: Move(key: "a", before: nil), in: row, sectionIDs: all, bias: .alternate))
        #expect(end.to.x == 214)
    }

    @Test("Placement is judged on the section's own row, not on the whole bar")
    func sectionRow() {
        // An item of another section stands between c and a on the bar.
        let e = Item(id: "e", minX: 130, maxX: 150, midY: 12)
        let c2 = Item(id: "c", minX: 100, maxX: 120, midY: 12)
        let a2 = Item(id: "a", minX: 160, maxX: 180, midY: 12)
        let bar = [c2, e, a2]
        #expect(ReorderDrag.isPlaced(Move(key: "c", before: "a"), in: bar, sectionIDs: ["a", "c"]))
        // On the whole bar e stands between them.
        #expect(!ReorderDrag.isPlaced(Move(key: "c", before: "a"), in: bar, sectionIDs: ["a", "c", "e"]))
    }

    @Test("Nothing is planned for an unknown id, a missing neighbour, a coordinate that is no number or an empty bar")
    func unusableInput() {
        #expect(ReorderDrag.step(for: Move(key: "zz", before: "a"), in: row, sectionIDs: all, bias: .primary) == nil)
        #expect(ReorderDrag.step(for: Move(key: "c", before: "zz"), in: row, sectionIDs: all, bias: .primary) == nil)
        #expect(ReorderDrag.step(for: Move(key: "c", before: "c"), in: row, sectionIDs: all, bias: .primary) == nil)
        #expect(ReorderDrag.step(for: Move(key: "c", before: "a"), in: [], sectionIDs: all, bias: .primary) == nil)
        let broken = Item(id: "a", minX: .nan, maxX: 120, midY: 12)
        #expect(ReorderDrag.step(for: Move(key: "c", before: "a"), in: [broken, b, c, d], sectionIDs: all, bias: .primary) == nil)
        let infinite = Item(id: "a", minX: 100, maxX: .infinity, midY: 12)
        #expect(!ReorderDrag.isPlaced(Move(key: "b", before: "c"), in: [infinite, b, c, d], sectionIDs: all))
        #expect(!ReorderDrag.isPlaced(Move(key: "zz", before: nil), in: row, sectionIDs: all))
        #expect(!ReorderDrag.isPlaced(Move(key: "a", before: nil), in: [], sectionIDs: all))
        // An id that is not in the section is not dragged.
        #expect(ReorderDrag.step(for: Move(key: "c", before: "a"), in: row, sectionIDs: ["a", "b", "d"], bias: .primary) == nil)
    }

    @Test("The bar's order does not have to be sorted: the planner sorts by position")
    func unsortedInput() throws {
        let step = try #require(ReorderDrag.step(for: Move(key: "c", before: "a"), in: [d, c, b, a], sectionIDs: all, bias: .primary))
        #expect(step.to.x == 99)
    }
}
