import Foundation
import Testing
@testable import HolzBarCore

@Suite("HubActivityBoard")
struct HubActivityBoardTests {
    typealias Board = HubActivityBoard

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func activity(
        _ id: String,
        module: String = "live-activities",
        priority: Int = 10,
        started: TimeInterval = 0,
        finished: TimeInterval? = nil
    ) -> LiveActivity {
        LiveActivity(
            id: id,
            moduleID: module,
            kind: .other,
            symbol: "star",
            title: id,
            priority: priority,
            startedAt: now.addingTimeInterval(started),
            finishedAt: finished.map { now.addingTimeInterval($0) }
        )
    }

    @Test("A higher priority goes first, then the newer start, then the key")
    func order() {
        let board = Board.board(
            [
                activity("old-low", priority: 10, started: -30),
                activity("capture", priority: 20, started: -60),
                activity("new-low", priority: 10, started: -5),
                activity("b-same", priority: 10, started: -5),
            ],
            now: now
        )
        #expect(board.listed.map(\.id) == ["capture", "b-same", "new-low", "old-low"])
        #expect(board.compact?.id == "capture")
        #expect(board.hiddenCount == 3)
    }

    @Test("Nothing live gives no compact activity, no hidden count and no expiry")
    func empty() {
        let board = Board.board([], now: now)
        #expect(board.listed.isEmpty)
        #expect(board.compact == nil)
        #expect(board.hiddenCount == 0)
        #expect(board.nextExpiry == nil)
    }

    @Test("One activity is the compact one and hides nothing")
    func single() {
        let board = Board.board([activity("only")], now: now)
        #expect(board.compact?.id == "only")
        #expect(board.listed.count == 1)
        #expect(board.hiddenCount == 0)
    }

    @Test("A finished activity stays for five seconds and is dropped at five or later")
    func finishedHold() {
        #expect(Board.finishedHold == 5)
        let justFinished = Board.board([activity("a", finished: 0)], now: now)
        #expect(justFinished.compact?.id == "a")
        let almost = Board.board([activity("a", finished: -4.9)], now: now)
        #expect(almost.compact?.id == "a")
        let atFive = Board.board([activity("a", finished: -5)], now: now)
        #expect(atFive.compact == nil)
        #expect(atFive.nextExpiry == nil)
        let later = Board.board([activity("a", finished: -60)], now: now)
        #expect(later.listed.isEmpty)
    }

    @Test("An activity that finishes in the future counts as running")
    func finishesInTheFuture() {
        let board = Board.board([activity("a", finished: 30)], now: now)
        #expect(board.compact?.id == "a")
        #expect(board.hiddenCount == 0)
    }

    @Test("The next expiry is the earliest finish plus five seconds that is after now")
    func nextExpiry() {
        let board = Board.board(
            [
                activity("running"),
                activity("first", finished: -4),
                activity("second", finished: -1),
                activity("gone", finished: -9),
            ],
            now: now
        )
        #expect(board.nextExpiry == now.addingTimeInterval(1))
        #expect(board.listed.count == 3)
        let none = Board.board([activity("running")], now: now)
        #expect(none.nextExpiry == nil)
    }

    @Test("Two activities with the same key keep the one that started later")
    func duplicates() {
        let board = Board.board(
            [
                activity("same", started: -20),
                activity("same", started: -2),
                activity("same", module: "other-module", started: -50),
            ],
            now: now
        )
        #expect(board.listed.count == 2)
        let kept = board.listed.first { $0.key == "live-activities/same" }
        #expect(kept?.startedAt == now.addingTimeInterval(-2))
        let reversed = Board.board([activity("same", started: -2), activity("same", started: -20)], now: now)
        #expect(reversed.listed.first?.startedAt == now.addingTimeInterval(-2))
        #expect(reversed.listed.count == 1)
    }

    @Test("More than five live activities list five and count every other one as hidden")
    func manyActivities() {
        let activities = (0..<8).map { activity("a\($0)", started: TimeInterval(-$0)) }
        let board = Board.board(activities, now: now)
        #expect(Board.maximumListed == 5)
        #expect(board.listed.count == 5)
        #expect(board.listed.map(\.id) == ["a0", "a1", "a2", "a3", "a4"])
        #expect(board.compact?.id == "a0")
        #expect(board.hiddenCount == 7)
    }

    @Test("An expired activity is not counted as hidden")
    func expiredIsNotHidden() {
        let board = Board.board([activity("live"), activity("gone", finished: -10)], now: now)
        #expect(board.hiddenCount == 0)
    }

    @Test("The input order does not change the board")
    func inputOrder() {
        let activities = [
            activity("a", priority: 10, started: -3),
            activity("b", priority: 20, started: -9),
            activity("c", priority: 10, started: -1),
        ]
        let forward = Board.board(activities, now: now)
        let backward = Board.board(activities.reversed(), now: now)
        #expect(forward == backward)
    }

    // MARK: LiveActivity

    @Test("A title is cut at 80 characters and a detail at 200")
    func textCaps() {
        let made = LiveActivity(
            id: "x",
            moduleID: "m",
            kind: .download,
            symbol: "arrow.down",
            title: String(repeating: "t", count: 120),
            detail: String(repeating: "d", count: 500),
            startedAt: now
        )
        #expect(made.title.count == 80)
        #expect(made.detail?.count == 200)
        let short = LiveActivity(id: "x", moduleID: "m", kind: .other, symbol: "star", title: "Short", startedAt: now)
        #expect(short.title == "Short")
        #expect(short.detail == nil)
    }

    @Test("A progress outside 0 to 1 is clamped and one that is no number is dropped")
    func progressClamp() {
        func progress(_ value: Double?) -> Double? {
            LiveActivity(
                id: "x", moduleID: "m", kind: .other, symbol: "star", title: "t", progress: value, startedAt: now
            ).progress
        }
        #expect(progress(0.4) == 0.4)
        #expect(progress(-3) == 0)
        #expect(progress(7) == 1)
        #expect(progress(.infinity) == 1)
        #expect(progress(.nan) == nil)
        #expect(progress(nil) == nil)
    }

    @Test("The key joins the module and the id, and an activity is identified by its id")
    func keys() {
        let made = LiveActivity(
            id: "camera", moduleID: "live-activities", kind: .capture, symbol: "camera.fill", title: "t", startedAt: now
        )
        #expect(made.key == "live-activities/camera")
        #expect(made.id == "camera")
        #expect(LiveActivityKind.allCases.map(\.rawValue) == ["capture", "download", "timer", "other"])
        #expect(LiveActivityTint.allCases.count == 4)
    }
}
