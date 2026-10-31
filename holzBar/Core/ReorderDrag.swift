//
//  ReorderDrag.swift
//  holzBar
//

import Foundation

/// The pure rules for putting the items of one menu bar section in order on macOS 27 with
/// synthetic ⌘-drags.
///
/// macOS 27 draws the items itself and lets the user move one with a ⌘-drag. holzBar does the
/// same drag, one item at a time: ``step(for:in:sectionIDs:bias:)`` turns a move of
/// ``ReorderPlan`` into the two points of one drag, ``isPlaced(_:in:sectionIDs:)`` judges from a
/// fresh read of the bar whether the item stands where it should, and ``Session`` drives a whole
/// run: it plans from every fresh read, retries a stalled move once with the other bias, and
/// stops at a capped number of steps. ``Preflight`` names why a run may not start. Nothing here
/// posts an event or reads the screen; the executor does, and passes in the frames it read.
nonisolated enum ReorderDrag {
    /// How far past a neighbour's near edge a drag to the left lands, in points.
    static let nearEdgeMargin: Double = 1
    /// How far past a neighbour's far edge a drag to the right or to the end lands, in points.
    /// It is the offset of the probe that showed macOS 27 accepts the drag.
    static let farEdgeMargin: Double = 2
    /// How far past a neighbour's midpoint the alternate bias lands, in points.
    static let midpointOffset: Double = 1
    /// How many moves beyond the first plan's a run may take before it gives up.
    static let extraSteps = 3
    /// How many drags one item gets before a run stops: the primary and the alternate.
    static let attemptsPerItem = 2

    /// A point on the screen, in the coordinates of the Accessibility frames.
    nonisolated struct Point: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    /// An item of the bar as the planner sees it: an identifier and where it stands.
    nonisolated struct Item: Equatable, Sendable {
        var id: String
        var minX: Double
        var maxX: Double
        var midY: Double

        var midX: Double { (minX + maxX) / 2 }

        /// Whether every coordinate is a number and the item has an extent.
        var isUsable: Bool {
            minX.isFinite && maxX.isFinite && midY.isFinite && minX <= maxX
        }
    }

    /// Where a drag aims.
    nonisolated enum Bias: Equatable, Sendable {
        /// Just past the neighbour's edge, as the probe did.
        case primary
        /// Just past the neighbour's midpoint, for a drag that did not land.
        case alternate
    }

    /// One drag: the item to take, where to press and where to let go.
    nonisolated struct Step: Equatable, Sendable {
        var id: String
        var from: Point
        var to: Point
        var bias: Bias
    }

    // MARK: Planner

    /// The drag that carries one item of a move to its place, or `nil` where it cannot be
    /// planned.
    ///
    /// - Parameters:
    ///   - move: The item and the item it goes before; `nil` for the end of the row.
    ///   - items: The bar's items in their current order from left to right, every item, the
    ///     ones that cannot move included.
    ///   - sectionIDs: The identifiers of the items of the section being sorted. The move is
    ///     judged on this row alone, so an item of another section between two of them does not
    ///     count.
    ///   - bias: Where the drag aims.
    /// - Returns: `nil` for an identifier that is not in the section or on the bar, a
    ///   coordinate that is not a number, or an item that already stands in its place.
    static func step(
        for move: ReorderPlan.Move,
        in items: [Item],
        sectionIDs: Set<String>,
        bias: Bias
    ) -> Step? {
        guard
            let row = row(of: items, sectionIDs: sectionIDs),
            let dragged = row.first(where: { $0.id == move.key }),
            !isPlacedInRow(move, row: row)
        else {
            return nil
        }
        let others = row.filter { $0.id != move.key }
        let neighbour: Item
        let toTheLeft: Bool
        if let before = move.before {
            guard before != move.key, let target = others.first(where: { $0.id == before }) else {
                return nil
            }
            if dragged.minX < target.minX {
                // The item moves right: it lands after the item that stands before the target.
                guard let predecessor = others.last(where: { $0.minX < target.minX }) else {
                    return nil
                }
                neighbour = predecessor
                toTheLeft = false
            } else {
                neighbour = target
                toTheLeft = true
            }
        } else {
            guard let last = others.last else {
                return nil
            }
            neighbour = last
            toTheLeft = false
        }
        let x: Double
        switch (toTheLeft, bias) {
        case (true, .primary): x = neighbour.minX - nearEdgeMargin
        case (false, .primary): x = neighbour.maxX + farEdgeMargin
        case (true, .alternate): x = neighbour.midX - midpointOffset
        case (false, .alternate): x = neighbour.midX + midpointOffset
        }
        return Step(
            id: dragged.id,
            from: Point(x: dragged.midX, y: dragged.midY),
            to: Point(x: x, y: dragged.midY),
            bias: bias
        )
    }

    /// Whether a move is done: the item stands directly before the other one in the section's
    /// row, or last in it for the end of the row. An unknown identifier counts as not placed.
    static func isPlaced(_ move: ReorderPlan.Move, in items: [Item], sectionIDs: Set<String>) -> Bool {
        guard let row = row(of: items, sectionIDs: sectionIDs) else {
            return false
        }
        return isPlacedInRow(move, row: row)
    }

    /// The items of the section from left to right, or `nil` when the bar cannot be judged:
    /// it is empty or an item has a coordinate that is not a number.
    private static func row(of items: [Item], sectionIDs: Set<String>) -> [Item]? {
        guard !items.isEmpty, items.allSatisfy(\.isUsable) else {
            return nil
        }
        return items.filter { sectionIDs.contains($0.id) }.sorted { $0.minX < $1.minX }
    }

    private static func isPlacedInRow(_ move: ReorderPlan.Move, row: [Item]) -> Bool {
        guard let index = row.firstIndex(where: { $0.id == move.key }) else {
            return false
        }
        guard let before = move.before else {
            return index == row.count - 1
        }
        guard before != move.key, let target = row.firstIndex(where: { $0.id == before }) else {
            return false
        }
        return index + 1 == target
    }

    // MARK: Session

    /// Why a run stopped before the section was in order. The raw values are used in the
    /// outcome line and in the diagnostics.
    nonisolated enum StopReason: String, Equatable, Sendable {
        /// A drag changed nothing, twice.
        case noProgress
        /// The run took more steps than the first plan and the allowance.
        case tooManySteps
        /// The planned item is not on the bar any more, or has no usable frame.
        case itemMissing
        /// The run was cancelled or the user kept using the mouse.
        case interrupted
    }

    /// What a run does next.
    nonisolated enum Decision: Equatable, Sendable {
        case drag(Step)
        case finished
        case stopped(StopReason)
    }

    /// A run that puts one section in order, one drag at a time.
    ///
    /// Every call of ``next(order:)`` takes a fresh read of the bar and plans from it: the
    /// moves ``ReorderPlan`` gives for the section's current row. If the number of planned moves
    /// did not go down since the last drag, that drag did not land: the same item is dragged
    /// again with the alternate bias, and a second miss stops the run. The run is capped at the
    /// first plan's number of moves plus ``ReorderDrag/extraSteps``.
    nonisolated struct Session: Equatable, Sendable {
        /// The wanted order of the section, by identifier.
        let desired: [String]
        /// The identifiers of the items that may be dragged. Anything else is never moved.
        let movable: Set<String>

        /// How many drags landed so far: the planned moves went down after them.
        private(set) var moved = 0
        /// How many drags were made.
        private(set) var steps = 0

        private var cap: Int?
        private var lastCount: Int?
        private var lastID: String?
        private var attempts = [String: Int]()

        init(desired: [String], movable: Set<String>) {
            self.desired = desired
            self.movable = movable
        }

        /// The next decision, from a fresh read of the bar.
        ///
        /// - Parameter order: Every item of the bar in its current order from left to right.
        mutating func next(order: [Item]) -> Decision {
            let row = order.filter { movable.contains($0.id) }.sorted { $0.minX < $1.minX }
            let moves = ReorderPlan.moves(actual: row.map(\.id), desired: desired)
            if cap == nil {
                cap = moves.count + ReorderDrag.extraSteps
            }
            if let lastCount, let lastID {
                if moves.count < lastCount {
                    moved += lastCount - moves.count
                    attempts[lastID] = 0
                } else if attempts[lastID, default: 0] >= ReorderDrag.attemptsPerItem {
                    return .stopped(.noProgress)
                }
            }
            guard let first = moves.first else {
                return .finished
            }
            if steps >= (cap ?? 0) {
                return .stopped(.tooManySteps)
            }
            // A drag that did not land is tried again for the same item.
            let retry = lastID.flatMap { id in
                moves.first { $0.key == id && attempts[id, default: 0] > 0 }
            }
            let move = retry ?? first
            let bias: Bias = attempts[move.key, default: 0] == 0 ? .primary : .alternate
            guard let step = ReorderDrag.step(for: move, in: order, sectionIDs: movable, bias: bias) else {
                return .stopped(.itemMissing)
            }
            attempts[move.key, default: 0] += 1
            steps += 1
            lastID = move.key
            lastCount = moves.count
            return .drag(step)
        }
    }

    // MARK: Preflight

    /// The conditions that keep a run from starting, or end it between two drags.
    nonisolated enum Preflight {
        /// Why a run may not go on. The raw values are used in the diagnostics.
        nonisolated enum Blocker: String, Equatable, Sendable {
            /// Accessibility is not granted.
            case notTrusted
            /// The bar is not fully revealed: Menu Bar Layout is not open.
            case barNotRevealed
            /// A mouse button is down: the user is using the mouse.
            case buttonDown
            /// The bar is not on the display with the active menu bar.
            case notOnActiveDisplay
            /// Another run is going.
            case alreadyRunning
            /// An earlier run showed that macOS does not accept the events, so sorting is off
            /// for the rest of the session.
            case turnedOffThisSession
        }

        /// The first condition that applies, in the fixed order of the cases above, or `nil`.
        static func blocker(
            isTrusted: Bool,
            barIsRevealed: Bool,
            buttonIsDown: Bool,
            isOnActiveDisplay: Bool,
            isRunning: Bool,
            isBlockedThisSession: Bool
        ) -> Blocker? {
            if !isTrusted {
                return .notTrusted
            }
            if !barIsRevealed {
                return .barNotRevealed
            }
            if buttonIsDown {
                return .buttonDown
            }
            if !isOnActiveDisplay {
                return .notOnActiveDisplay
            }
            if isRunning {
                return .alreadyRunning
            }
            if isBlockedThisSession {
                return .turnedOffThisSession
            }
            return nil
        }
    }
}
