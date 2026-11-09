import Foundation
import Testing
@testable import HolzBarCore

@Suite("MoveNeighbourCheck")
struct MoveNeighbourCheckTests {
    private typealias Entry = MoveNeighbourCheck.Entry

    private func entries(_ pairs: [(UInt32, Double)]) -> [Entry] {
        pairs.map { Entry(id: $0.0, minX: $0.1) }
    }

    @Test("The same order before and after disturbs nothing")
    func sameOrder() {
        let before = entries([(1, 0), (2, 10), (3, 20)])
        let after = entries([(1, 5), (2, 15), (3, 25)])
        #expect(MoveNeighbourCheck.disturbed(before: before, after: after, moved: 2).isEmpty)
    }

    @Test("The moved item crossing the others disturbs nothing")
    func movedItemCrosses() {
        let before = entries([(1, 0), (2, 10), (3, 20), (9, 30)])
        let after = entries([(9, 0), (1, 10), (2, 20), (3, 30)])
        #expect(MoveNeighbourCheck.disturbed(before: before, after: after, moved: 9).isEmpty)
    }

    @Test("Two neighbours that swap while another item moved disturb one item")
    func neighboursSwap() {
        let before = entries([(1, 0), (2, 10), (3, 20)])
        let after = entries([(2, 0), (1, 10), (3, 20)])
        let result = MoveNeighbourCheck.disturbed(before: before, after: after, moved: 3)
        #expect(result.count == 1)
        #expect(result == [1] || result == [2])
    }

    @Test("An id that is missing after the move or new after it is ignored")
    func missingAndNewIdsAreIgnored() {
        let before = entries([(1, 0), (2, 10), (3, 20)])
        let after = entries([(1, 0), (4, 5), (3, 20)])
        #expect(MoveNeighbourCheck.disturbed(before: before, after: after, moved: 3).isEmpty)
    }

    @Test("Equal positions are ordered by id, and the result is sorted")
    func equalPositionsAreDeterministic() {
        let before = entries([(5, 0), (4, 10), (3, 20), (2, 30), (1, 40), (9, 50)])
        let after = entries([(1, 0), (2, 10), (3, 20), (4, 30), (5, 40), (9, 50)])
        let first = MoveNeighbourCheck.disturbed(before: before, after: after, moved: 9)
        let second = MoveNeighbourCheck.disturbed(before: before, after: after, moved: 9)
        #expect(first == second)
        #expect(first == first.sorted())
        #expect(first.count == 4)

        let tied = entries([(2, 0), (1, 0), (3, 10)])
        #expect(MoveNeighbourCheck.disturbed(before: tied, after: tied, moved: 3).isEmpty)
    }

    @Test("A window outside the managed set never counts")
    func unmanagedWindowsAreIgnored() {
        // Window 7 is a system clone of the moved item 3: it follows the item across 1 and 2.
        let before = entries([(7, -10), (1, 0), (2, 10), (3, 20)])
        let after = entries([(1, 0), (2, 10), (3, 20), (7, 30)])
        #expect(MoveNeighbourCheck.disturbed(before: before, after: after, moved: 3) == [7])
        #expect(MoveNeighbourCheck.disturbed(before: before, after: after, moved: 3, managed: [1, 2, 3]).isEmpty)
        // A managed neighbour that was pushed still counts.
        let pushed = entries([(2, 0), (1, 10), (3, 20), (7, 30)])
        #expect(MoveNeighbourCheck.disturbed(before: before, after: pushed, moved: 3, managed: [1, 2, 3]).count == 1)
    }

    @Test("An empty bar disturbs nothing")
    func emptyLists() {
        #expect(MoveNeighbourCheck.disturbed(before: [], after: [], moved: 1).isEmpty)
    }

    @Test("Only an automatic move outside a pass or in a restore schedules a repair")
    func repairPolicy() {
        #expect(MoveNeighbourCheck.schedulesRepair(automatic: true, pass: nil))
        #expect(MoveNeighbourCheck.schedulesRepair(automatic: true, pass: .restore))
        #expect(!MoveNeighbourCheck.schedulesRepair(automatic: true, pass: .arrangement))
        #expect(!MoveNeighbourCheck.schedulesRepair(automatic: true, pass: .repair))
        for pass: MoveNeighbourCheck.Pass? in [nil, .restore, .arrangement, .repair] {
            #expect(!MoveNeighbourCheck.schedulesRepair(automatic: false, pass: pass))
        }
    }
}
