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

    // MARK: Session

    /// A bar with the items in the given order, 24 points wide with 6 points between them.
    private func bar(_ ids: [String]) -> [Item] {
        ids.enumerated().map { index, id in
            let minX = 100 + Double(index) * 30
            return Item(id: id, minX: minX, maxX: minX + 24, midY: 12)
        }
    }

    /// The order after a move landed.
    private func apply(_ move: Move, to ids: [String]) -> [String] {
        var result = ids.filter { $0 != move.key }
        if let before = move.before, let index = result.firstIndex(of: before) {
            result.insert(move.key, at: index)
        } else {
            result.append(move.key)
        }
        return result
    }

    /// Runs a session against a bar where every planned drag lands, and returns the decisions.
    private func simulate(
        from start: [String],
        desired: [String],
        movable: Set<String>
    ) -> (decisions: [ReorderDrag.Decision], session: ReorderDrag.Session) {
        var session = ReorderDrag.Session(desired: desired, movable: movable)
        var ids = start
        var decisions = [ReorderDrag.Decision]()
        for _ in 0..<20 {
            let decision = session.next(order: bar(ids))
            decisions.append(decision)
            guard case .drag = decision else {
                break
            }
            let movableIDs = ids.filter { movable.contains($0) }
            guard let move = ReorderPlan.moves(actual: movableIDs, desired: desired).first else {
                break
            }
            ids = apply(move, to: ids)
        }
        return (decisions, session)
    }

    @Test("One item out of place takes one drag, and the next read finishes the run")
    func oneDrag() throws {
        var session = ReorderDrag.Session(desired: ["d", "a", "b", "c"], movable: all)
        let first = session.next(order: bar(["a", "b", "c", "d"]))
        guard case .drag(let step) = first else {
            Issue.record("expected a drag, got \(first)")
            return
        }
        #expect(step.id == "d")
        #expect(step.bias == .primary)
        #expect(session.next(order: bar(["d", "a", "b", "c"])) == .finished)
        #expect(session.steps == 1)
        #expect(session.moved == 1)
    }

    @Test("Two moves are planned one after the other, each from a fresh read")
    func twoMoves() {
        let desired = ["b", "a", "d", "c"]
        let planned = ReorderPlan.moves(actual: ["a", "b", "c", "d"], desired: desired)
        #expect(planned.count == 2)
        let run = simulate(from: ["a", "b", "c", "d"], desired: desired, movable: all)
        #expect(run.decisions.last == .finished)
        #expect(run.session.steps == 2)
        #expect(run.session.moved == 2)
    }

    @Test("A drag that changes nothing is retried once with the other bias, then the run stops")
    func noProgress() {
        var session = ReorderDrag.Session(desired: ["d", "a", "b", "c"], movable: all)
        let stuck = bar(["a", "b", "c", "d"])
        guard case .drag(let primary) = session.next(order: stuck) else {
            Issue.record("expected a first drag")
            return
        }
        guard case .drag(let alternate) = session.next(order: stuck) else {
            Issue.record("expected a retry")
            return
        }
        #expect(primary.id == alternate.id)
        #expect(primary.bias == .primary)
        #expect(alternate.bias == .alternate)
        #expect(session.next(order: stuck) == .stopped(.noProgress))
        #expect(session.moved == 0)
    }

    @Test("A stall after one landed move stops with no progress and keeps the count of moves that landed")
    func stallAfterProgress() {
        let desired = ["b", "a", "d", "c"]
        var session = ReorderDrag.Session(desired: desired, movable: all)
        var ids = ["a", "b", "c", "d"]
        guard case .drag = session.next(order: bar(ids)) else {
            Issue.record("expected the first drag")
            return
        }
        ids = apply(ReorderPlan.moves(actual: ids, desired: desired)[0], to: ids)
        guard case .drag = session.next(order: bar(ids)) else {
            Issue.record("expected the second drag")
            return
        }
        guard case .drag = session.next(order: bar(ids)) else {
            Issue.record("expected the retry")
            return
        }
        #expect(session.next(order: bar(ids)) == .stopped(.noProgress))
        #expect(session.moved == 1)
    }

    @Test("A run that keeps changing the order without converging stops after the first plan's moves plus three")
    func stepCap() {
        let desired = ["a", "b", "c", "d"]
        let twoOff = ["b", "a", "d", "c"]
        let oneOff = ["a", "b", "d", "c"]
        #expect(ReorderPlan.moves(actual: twoOff, desired: desired).count == 2)
        #expect(ReorderPlan.moves(actual: oneOff, desired: desired).count == 1)
        var session = ReorderDrag.Session(desired: desired, movable: all)
        var decisions = [ReorderDrag.Decision]()
        for index in 0..<12 {
            let decision = session.next(order: bar(index.isMultiple(of: 2) ? twoOff : oneOff))
            decisions.append(decision)
            if case .drag = decision {
                continue
            }
            break
        }
        #expect(decisions.last == .stopped(.tooManySteps))
        #expect(session.steps == 5)
    }

    @Test("An item that left the bar between steps is dropped from the plan")
    func itemLeavesTheBar() {
        var session = ReorderDrag.Session(desired: ["d", "a", "b", "c"], movable: all)
        guard case .drag(let step) = session.next(order: bar(["a", "b", "c", "d"])) else {
            Issue.record("expected a drag")
            return
        }
        #expect(step.id == "d")
        // d is gone; the others are in their order.
        #expect(session.next(order: bar(["a", "b", "c"])) == .finished)
    }

    @Test("Pinned items are never dragged and moves naming them are dropped")
    func pinnedItems() {
        // p is pinned: it stands in the bar and in the wanted order but is not movable.
        let movable: Set<String> = ["a", "b", "c"]
        let run = simulate(from: ["p", "a", "b", "c"], desired: ["c", "p", "a", "b"], movable: movable)
        for decision in run.decisions {
            if case .drag(let step) = decision {
                #expect(step.id != "p")
            }
        }
        #expect(run.decisions.last == .finished)
        #expect(run.session.steps == 1)
    }

    @Test("A planned item with no usable frame stops the run as missing")
    func unusableFrame() {
        var session = ReorderDrag.Session(desired: ["d", "a", "b", "c"], movable: all)
        var order = bar(["a", "b", "c", "d"])
        order[3] = Item(id: "d", minX: .nan, maxX: .nan, midY: 12)
        #expect(session.next(order: order) == .stopped(.itemMissing))
    }

    // MARK: Preflight

    @Test("The first blocker in the fixed order wins, and no blocker gives none")
    func preflightPriority() {
        typealias Blocker = ReorderDrag.Preflight.Blocker
        func blocker(
            trusted: Bool = true,
            revealed: Bool = true,
            button: Bool = false,
            display: Bool = true,
            running: Bool = false,
            blocked: Bool = false
        ) -> Blocker? {
            ReorderDrag.Preflight.blocker(
                isTrusted: trusted,
                barIsRevealed: revealed,
                buttonIsDown: button,
                isOnActiveDisplay: display,
                isRunning: running,
                isBlockedThisSession: blocked
            )
        }
        #expect(blocker() == nil)
        #expect(blocker(trusted: false, revealed: false, button: true, display: false, running: true, blocked: true) == .notTrusted)
        #expect(blocker(revealed: false, button: true, display: false, running: true, blocked: true) == .barNotRevealed)
        #expect(blocker(button: true, display: false, running: true, blocked: true) == .buttonDown)
        #expect(blocker(display: false, running: true, blocked: true) == .notOnActiveDisplay)
        #expect(blocker(running: true, blocked: true) == .alreadyRunning)
        #expect(blocker(blocked: true) == .turnedOffThisSession)
        #expect(Blocker.barNotRevealed.rawValue == "barNotRevealed")
        #expect(ReorderDrag.StopReason.noProgress.rawValue == "noProgress")
        #expect(ReorderDrag.StopReason.tooManySteps.rawValue == "tooManySteps")
        #expect(ReorderDrag.StopReason.itemMissing.rawValue == "itemMissing")
    }
}
