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

    // MARK: Moments

    @Test("A moment 90 seconds ahead runs to it; too soon, too far, past and not-a-number are refused")
    func momentLimits() {
        var board = TimerBoard()
        let moment = t.addingTimeInterval(90)
        #expect(board.startMoment(moment, label: "", now: t, id: id(1)) == .started(id(1)))
        #expect(board.items[0].state == .running(start: t, end: moment))
        #expect(board.items[0].kind == .moment(moment))

        var refused = TimerBoard()
        #expect(refused.startMoment(t.addingTimeInterval(1), label: "", now: t) == .refused(.momentTooSoon))
        #expect(refused.startMoment(t.addingTimeInterval(-60), label: "", now: t) == .refused(.momentTooSoon))
        #expect(refused.startMoment(Date(timeIntervalSinceReferenceDate: .nan), label: "", now: t) == .refused(.momentTooSoon))
        #expect(refused.startMoment(t.addingTimeInterval(2), label: "", now: t, id: id(2)) == .started(id(2)))
        let day: Double = 24 * 60 * 60
        #expect(refused.startMoment(t.addingTimeInterval(366 * day), label: "", now: t, id: id(3)) == .started(id(3)))
        #expect(refused.startMoment(t.addingTimeInterval(366 * day + 1), label: "", now: t) == .refused(.momentTooFar))
        #expect(refused.items.count == 2)
    }

    // MARK: Pause, resume, restart, remove

    @Test("Pausing keeps the seconds left, waiting changes nothing, and resuming runs for them from then on")
    func pauseAndResume() {
        var board = TimerBoard()
        _ = board.startLength(300, label: "", now: t, id: id(1))
        #expect(board.pause(id(1), now: t.addingTimeInterval(100)) == true)
        #expect(board.items[0].state == .paused(remaining: 200, total: 300))
        #expect(board.remaining(of: id(1), now: t.addingTimeInterval(5_000)) == 200)
        #expect(board.nextDeadline == nil)
        #expect(board.pause(id(1), now: t.addingTimeInterval(120)) == false)

        let later = t.addingTimeInterval(1_000)
        #expect(board.resume(id(1), now: later) == true)
        #expect(board.items[0].state == .running(start: later.addingTimeInterval(-100), end: later.addingTimeInterval(200)))
        #expect(board.nextDeadline == later.addingTimeInterval(200))
        let progress = board.fraction(of: id(1), now: later) ?? -1
        #expect(abs(progress - 1.0 / 3.0) < 1e-9)
        #expect(board.resume(id(1), now: later) == false)
    }

    @Test("A moment cannot be paused, and a finished or unknown timer cannot either")
    func pauseRefusals() {
        var board = TimerBoard()
        _ = board.startMoment(t.addingTimeInterval(90), label: "", now: t, id: id(1))
        _ = board.startLength(10, label: "", now: t, id: id(2))
        let before = board
        #expect(board.pause(id(1), now: t.addingTimeInterval(1)) == false)
        #expect(board.pause(id(3), now: t) == false)
        #expect(board == before)
        _ = board.collectFinished(now: t.addingTimeInterval(10))
        #expect(board.pause(id(2), now: t.addingTimeInterval(11)) == false)
        #expect(board.resume(id(2), now: t.addingTimeInterval(11)) == false)
    }

    @Test("Restart runs a length timer for its full length again in any state; a moment cannot restart")
    func restart() {
        var board = TimerBoard()
        _ = board.startLength(60, label: "", now: t, id: id(1))
        _ = board.startMoment(t.addingTimeInterval(90), label: "", now: t, id: id(2))
        _ = board.collectFinished(now: t.addingTimeInterval(61))
        let later = t.addingTimeInterval(500)
        #expect(board.restart(id(1), now: later) == true)
        #expect(board.items[0].state == .running(start: later, end: later.addingTimeInterval(60)))
        // A running timer starts over.
        let again = later.addingTimeInterval(20)
        #expect(board.restart(id(1), now: again) == true)
        #expect(board.items[0].state == .running(start: again, end: again.addingTimeInterval(60)))
        // A paused timer runs for its full length.
        board.pause(id(1), now: again.addingTimeInterval(5))
        #expect(board.restart(id(1), now: again.addingTimeInterval(10)) == true)
        #expect(board.items[0].state == .running(start: again.addingTimeInterval(10), end: again.addingTimeInterval(70)))
        #expect(board.restart(id(2), now: later) == false)
        #expect(board.restart(id(9), now: later) == false)
    }

    @Test("Removing one timer keeps the others in order, an unknown id changes nothing, and removeFinished takes only finished ones")
    func removing() {
        var board = TimerBoard()
        _ = board.startLength(10, label: "", now: t, id: id(1))
        _ = board.startLength(500, label: "", now: t, id: id(2))
        _ = board.startLength(600, label: "", now: t, id: id(3))
        #expect(board.remove(id(2)) == true)
        #expect(board.items.map(\.id) == [id(1), id(3)])
        let before = board
        #expect(board.remove(id(9)) == false)
        #expect(board == before)
        _ = board.collectFinished(now: t.addingTimeInterval(11))
        #expect(board.removeFinished() == true)
        #expect(board.items.map(\.id) == [id(3)])
        #expect(board.removeFinished() == false)
    }

    // MARK: Limits

    @Test("A full board drops its oldest finished timer for a ninth; with none finished it refuses as full")
    func fullBoard() {
        var board = TimerBoard()
        for number in 1...8 {
            #expect(board.startLength(Double(number * 10), label: "", now: t, id: id(number)) == .started(id(number)))
        }
        #expect(board.startLength(500, label: "", now: t, id: id(9)) == .refused(.full))
        #expect(board.startMoment(t.addingTimeInterval(500), label: "", now: t, id: id(9)) == .refused(.full))
        #expect(board.items.count == 8)

        // Timers 1, 2 and 3 finish, timer 1 first: it is the oldest finished one.
        _ = board.collectFinished(now: t.addingTimeInterval(30))
        #expect(board.startLength(500, label: "", now: t, id: id(9)) == .started(id(9)))
        #expect(board.items.count == 8)
        #expect(!board.items.map(\.id).contains(id(1)))
        #expect(board.items.map(\.id).contains(id(2)))
        #expect(board.startLength(500, label: "", now: t, id: id(10)) == .started(id(10)))
        #expect(!board.items.map(\.id).contains(id(2)))
        #expect(board.startLength(500, label: "", now: t, id: id(11)) == .started(id(11)))
        #expect(!board.items.map(\.id).contains(id(3)))
        #expect(board.startLength(500, label: "", now: t, id: id(12)) == .refused(.full))
    }

    @Test("Labels are trimmed, line breaks become spaces, long labels are cut to 40 and empty stays empty")
    func labels() {
        #expect(TimerBoard.cleanLabel("  Tea  ") == "Tea")
        #expect(TimerBoard.cleanLabel("Tea\nand\r\ncake") == "Tea and cake")
        #expect(TimerBoard.cleanLabel(String(repeating: "x", count: 60)) == String(repeating: "x", count: 40))
        #expect(TimerBoard.cleanLabel("") == "")
        #expect(TimerBoard.cleanLabel(" \n ") == "")
        var board = TimerBoard()
        _ = board.startLength(60, label: "  Pasta\n", now: t, id: id(1))
        #expect(board.items[0].label == "Pasta")
    }

    // MARK: Progress, order

    @Test("Progress is 0 at the start, half halfway, 1 at and after the end, 1 when finished, and a paused timer keeps its share")
    func progress() {
        var board = TimerBoard()
        _ = board.startLength(100, label: "", now: t, id: id(1))
        #expect(board.fraction(of: id(1), now: t) == 0)
        #expect(board.fraction(of: id(1), now: t.addingTimeInterval(50)) == 0.5)
        #expect(board.fraction(of: id(1), now: t.addingTimeInterval(100)) == 1)
        #expect(board.fraction(of: id(1), now: t.addingTimeInterval(900)) == 1)
        #expect(board.fraction(of: id(1), now: t.addingTimeInterval(-5)) == 0)
        #expect(board.fraction(of: id(9), now: t) == nil)
        _ = board.collectFinished(now: t.addingTimeInterval(101))
        #expect(board.fraction(of: id(1), now: t) == 1)
        // A paused timer's progress is the share that has been used up.
        _ = board.startLength(100, label: "", now: t, id: id(2))
        board.pause(id(2), now: t.addingTimeInterval(25))
        #expect(board.fraction(of: id(2), now: t.addingTimeInterval(500)) == 0.25)
    }

    @Test("The display order is finished, then running, then paused, with ties in the order the timers were added")
    func displayOrder() {
        var board = TimerBoard()
        _ = board.startLength(900, label: "", now: t, id: id(1))   // running, latest end
        _ = board.startLength(100, label: "", now: t, id: id(2))   // finishes first
        _ = board.startLength(300, label: "", now: t, id: id(3))   // running
        _ = board.startLength(200, label: "", now: t, id: id(4))   // finishes second
        _ = board.startLength(300, label: "", now: t, id: id(5))   // running, same end as 3
        _ = board.startLength(800, label: "", now: t, id: id(6))   // paused with the most left
        _ = board.startLength(700, label: "", now: t, id: id(7))   // paused with less left
        board.pause(id(6), now: t.addingTimeInterval(10))
        board.pause(id(7), now: t.addingTimeInterval(10))
        _ = board.collectFinished(now: t.addingTimeInterval(250))
        #expect(board.ordered.map(\.id) == [id(4), id(2), id(3), id(5), id(1), id(7), id(6)])
        #expect(board.leading?.id == id(4))
        #expect(board.hasRunning)
        #expect(TimerBoard().leading == nil)
        #expect(!TimerBoard().hasRunning)
    }

    @Test("The next deadline ignores paused and finished timers")
    func nextDeadlineIgnoresOthers() {
        var board = TimerBoard()
        _ = board.startLength(10, label: "", now: t, id: id(1))
        _ = board.startLength(20, label: "", now: t, id: id(2))
        _ = board.startLength(600, label: "", now: t, id: id(3))
        board.pause(id(2), now: t.addingTimeInterval(1))
        _ = board.collectFinished(now: t.addingTimeInterval(11))
        #expect(board.nextDeadline == t.addingTimeInterval(600))
    }

    // MARK: Stored form

    private func sampleBoard() -> TimerBoard {
        var board = TimerBoard()
        _ = board.startLength(300, label: "Tea “green” é", now: t, id: id(1))
        _ = board.startMoment(t.addingTimeInterval(7_200), label: "Fri \"17:00\"", now: t, id: id(2))
        _ = board.startLength(60, label: "", now: t, id: id(3))
        _ = board.startLength(900, label: "Paused", now: t, id: id(4))
        board.pause(id(4), now: t.addingTimeInterval(100))
        _ = board.collectFinished(now: t.addingTimeInterval(61))
        return board
    }

    @Test("A board and its stored form give an equal board: running, paused and finished, length and moment")
    func storedRoundTrip() {
        let board = sampleBoard()
        #expect(board.items.count == 4)
        let again = TimerBoard.decoded(from: board.encoded())
        #expect(again == board)
        #expect(TimerBoard.decoded(from: TimerBoard().encoded()) == TimerBoard())
    }

    @Test("The stored form is version 1 with the documented keys")
    func storedKeys() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: sampleBoard().encoded()) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        let items = try #require(object["items"] as? [[String: Any]])
        #expect(items.count == 4)
        let tea = items[0]
        #expect(tea["id"] as? String == id(1).uuidString)
        #expect(tea["label"] as? String == "Tea “green” é")
        #expect(tea["kind"] as? String == "length")
        #expect(tea["seconds"] as? Double == 300)
        #expect(tea["state"] as? String == "running")
        #expect(tea["start"] as? Double == t.timeIntervalSince1970)
        #expect(tea["end"] as? Double == t.timeIntervalSince1970 + 300)
        #expect(items[1]["kind"] as? String == "moment")
        #expect(items[1]["moment"] as? Double == t.timeIntervalSince1970 + 7_200)
        #expect(items[2]["state"] as? String == "finished")
        #expect(items[2]["at"] as? Double == t.timeIntervalSince1970 + 60)
        #expect(items[3]["state"] as? String == "paused")
        #expect(items[3]["remaining"] as? Double == 800)
        #expect(items[3]["total"] as? Double == 900)
    }

    @Test("Damaged input gives an empty board: no data, empty data, text, a JSON array, version 2, no version")
    func damagedBoards() {
        let empty = TimerBoard()
        #expect(TimerBoard.decoded(from: nil) == empty)
        #expect(TimerBoard.decoded(from: Data()) == empty)
        #expect(TimerBoard.decoded(from: Data("not json at all".utf8)) == empty)
        #expect(TimerBoard.decoded(from: Data("[1,2,3]".utf8)) == empty)
        #expect(TimerBoard.decoded(from: Data("\"text\"".utf8)) == empty)
        #expect(TimerBoard.decoded(from: Data("{\"version\":2,\"items\":[]}".utf8)) == empty)
        #expect(TimerBoard.decoded(from: Data("{\"items\":[]}".utf8)) == empty)
        #expect(TimerBoard.decoded(from: Data("{\"version\":1}".utf8)) == empty)
        #expect(TimerBoard.decoded(from: Data("{\"version\":1,\"items\":5}".utf8)) == empty)
        #expect(TimerBoard.decoded(from: Data(repeating: 0x20, count: 300_000)) == empty)
        let bytes = Data([0xFF, 0xFE, 0x00, 0x7B])
        #expect(TimerBoard.decoded(from: bytes) == empty)
    }

    private func decoded(items: [String]) -> TimerBoard {
        TimerBoard.decoded(from: Data("{\"version\":1,\"items\":[\(items.joined(separator: ","))]}".utf8))
    }

    private func item(
        _ number: Int,
        kind: String = "\"length\",\"seconds\":300",
        state: String = "\"running\",\"start\":1800000000,\"end\":1800000300"
    ) -> String {
        "{\"id\":\"\(id(number).uuidString)\",\"label\":\"x\",\"kind\":\(kind),\"state\":\(state)}"
    }

    @Test("A bad item is dropped and the others stay")
    func badItemsAreDropped() {
        let good = item(1)
        let bad: [String] = [
            "{\"id\":\"not-a-uuid\",\"kind\":\"length\",\"seconds\":300,\"state\":\"finished\",\"at\":1800000000}",
            "{\"id\":\"\(id(2).uuidString)\",\"kind\":\"alarm\",\"seconds\":300,\"state\":\"finished\",\"at\":1800000000}",
            "{\"id\":\"\(id(3).uuidString)\",\"kind\":\"length\",\"seconds\":300,\"state\":\"sleeping\"}",
            "{\"id\":\"\(id(4).uuidString)\",\"kind\":\"length\",\"state\":\"finished\",\"at\":1800000000}",
            "{\"id\":\"\(id(5).uuidString)\",\"kind\":\"length\",\"seconds\":0,\"state\":\"finished\",\"at\":1800000000}",
            "{\"id\":\"\(id(6).uuidString)\",\"kind\":\"length\",\"seconds\":400000,\"state\":\"finished\",\"at\":1800000000}",
            "{\"id\":\"\(id(7).uuidString)\",\"kind\":\"length\",\"seconds\":300,\"state\":\"running\",\"start\":1800000300,\"end\":1800000300}",
            "{\"id\":\"\(id(8).uuidString)\",\"kind\":\"length\",\"seconds\":300,\"state\":\"running\",\"start\":1800000300,\"end\":1800000000}",
            "{\"id\":\"\(id(9).uuidString)\",\"kind\":\"length\",\"seconds\":300,\"state\":\"running\",\"start\":\"soon\",\"end\":1800000300}",
            "{\"id\":\"\(id(10).uuidString)\",\"kind\":\"length\",\"seconds\":300,\"state\":\"running\",\"start\":1800000000,\"end\":1e300}",
            "{\"id\":\"\(id(11).uuidString)\",\"kind\":\"length\",\"seconds\":300,\"state\":\"paused\",\"remaining\":0,\"total\":300}",
            "{\"id\":\"\(id(12).uuidString)\",\"kind\":\"length\",\"seconds\":300,\"state\":\"paused\",\"remaining\":400,\"total\":300}",
            "{\"id\":\"\(id(13).uuidString)\",\"kind\":\"moment\",\"moment\":1800000100,\"state\":\"paused\",\"remaining\":5,\"total\":10}",
            "{\"id\":\"\(id(14).uuidString)\",\"kind\":\"moment\",\"moment\":null,\"state\":\"finished\",\"at\":1}",
            "42",
            "\"text\"",
            "null",
            "[]",
        ]
        #expect(decoded(items: [good]).items.map(\.id) == [id(1)])
        for entry in bad {
            let board = decoded(items: [entry, good])
            #expect(board.items.map(\.id) == [id(1)], "\(entry)")
        }
        #expect(decoded(items: bad + [good]).items.map(\.id) == [id(1)])
    }

    @Test("A duplicate id keeps the first; nine items keep the first eight; labels are cleaned")
    func duplicatesAndCount() {
        let first = "{\"id\":\"\(id(1).uuidString)\",\"label\":\"first\",\"kind\":\"length\",\"seconds\":60,\"state\":\"finished\",\"at\":1800000000}"
        let second = "{\"id\":\"\(id(1).uuidString)\",\"label\":\"second\",\"kind\":\"length\",\"seconds\":60,\"state\":\"finished\",\"at\":1800000000}"
        let board = decoded(items: [first, second])
        #expect(board.items.count == 1)
        #expect(board.items[0].label == "first")

        let nine = decoded(items: (1...9).map { item($0) })
        #expect(nine.items.map(\.id) == (1...8).map { id($0) })

        let long = "{\"id\":\"\(id(2).uuidString)\",\"label\":\"  \(String(repeating: "y", count: 80))\\n\",\"kind\":\"length\",\"seconds\":60,\"state\":\"finished\",\"at\":1800000000}"
        #expect(decoded(items: [long]).items.first?.label == String(repeating: "y", count: 40))
    }

    @Test("A running moment is kept up to 366 days and a running length up to its longest")
    func spansAreChecked() {
        let year = item(1, kind: "\"moment\",\"moment\":1831622400", state: "\"running\",\"start\":1800000000,\"end\":1831622400")
        let tooFar = item(2, kind: "\"moment\",\"moment\":1831622401", state: "\"running\",\"start\":1800000000,\"end\":1831622401")
        let longLength = item(3, state: "\"running\",\"start\":1800000000,\"end\":1800360000")
        #expect(decoded(items: [year, tooFar, longLength]).items.map(\.id) == [id(1)])
    }
}
