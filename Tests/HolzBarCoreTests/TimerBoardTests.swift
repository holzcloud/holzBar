import Foundation
import Testing
@testable import HolzBarCore

@Suite("TimerBoard")
struct TimerBoardTests {
    /// A fixed reference moment; no clock is read.
    private let t = Date(timeIntervalSince1970: 1_800_000_000)

    private func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
    }

    @Test("A length of 300 seconds runs from the start to 300 seconds later and counts down")
    func lengthRunsAndCountsDown() {
        var board = TimerBoard()
        let result = board.startLength(300, label: "", now: t, id: id(1))
        #expect(result == .started(id(1)))
        #expect(board.items.count == 1)
        #expect(board.items[0].state == .running(start: t, end: t.addingTimeInterval(300)))
        #expect(board.remaining(of: id(1), now: t.addingTimeInterval(100)) == 200)
        #expect(board.remaining(of: id(1), now: t.addingTimeInterval(400)) == 0)
        #expect(board.remaining(of: id(2), now: t) == nil)
    }

    @Test("Lengths out of range are refused and leave the board unchanged; the limits are accepted")
    func lengthLimits() {
        var board = TimerBoard()
        for seconds in [0, -5, .nan, .infinity, -.infinity, 360_000, 0.5] as [Double] {
            #expect(board.startLength(seconds, label: "", now: t) == .refused(.lengthOutOfRange))
        }
        #expect(board.items.isEmpty)
        #expect(board.startLength(1, label: "", now: t, id: id(1)) == .started(id(1)))
        #expect(board.startLength(359_999, label: "", now: t, id: id(2)) == .started(id(2)))
        #expect(board.items.count == 2)
    }

    @Test("The next deadline is the earliest end among the running timers and nil on an empty board")
    func nextDeadline() {
        var board = TimerBoard()
        #expect(board.nextDeadline == nil)
        _ = board.startLength(600, label: "", now: t, id: id(1))
        _ = board.startLength(120, label: "", now: t, id: id(2))
        _ = board.startLength(300, label: "", now: t, id: id(3))
        #expect(board.nextDeadline == t.addingTimeInterval(120))
    }

    @Test("Finishing marks a timer at its end, rings within fifteen seconds and misses later, and reports it once")
    func collectFinished() {
        var board = TimerBoard()
        _ = board.startLength(10, label: "", now: t, id: id(1))
        let end = t.addingTimeInterval(10)

        // Before the end nothing happens.
        var before = board
        #expect(before.collectFinished(now: end.addingTimeInterval(-1)) == TimerBoard.Finished())
        #expect(before == board)

        var atEnd = board
        #expect(atEnd.collectFinished(now: end).rang == [id(1)])
        #expect(atEnd.items[0].state == .finished(at: end))
        #expect(atEnd.collectFinished(now: end.addingTimeInterval(1)) == TimerBoard.Finished())

        var late = board
        #expect(late.collectFinished(now: end.addingTimeInterval(1)).rang == [id(1)])
        var edge = board
        #expect(edge.collectFinished(now: end.addingTimeInterval(15)).rang == [id(1)])
        var missed = board
        let result = missed.collectFinished(now: end.addingTimeInterval(16))
        #expect(result.rang.isEmpty)
        #expect(result.missed == [id(1)])
        #expect(missed.items[0].state == .finished(at: end))
    }

    @Test("Timers that end together are reported in the order they ended, rung apart from missed")
    func finishedInEndOrder() {
        var board = TimerBoard()
        _ = board.startLength(100, label: "", now: t, id: id(1))
        _ = board.startLength(20, label: "", now: t, id: id(2))
        _ = board.startLength(60, label: "", now: t, id: id(3))
        let result = board.collectFinished(now: t.addingTimeInterval(110))
        #expect(result.missed == [id(2), id(3)])
        #expect(result.rang == [id(1)])
    }
}
