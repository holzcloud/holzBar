import Foundation
import Testing
@testable import HolzBarCore

@Suite("TimerLiveActivities")
struct TimerLiveActivitiesTests {
    private let t = Date(timeIntervalSince1970: 1_800_000_000)
    private let words = TimerLiveActivities.Words(running: "Timer", done: "Done")

    private func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID()
    }

    private func activities(_ board: TimerBoard) -> [LiveActivity] {
        TimerLiveActivities.activities(for: board, moduleID: "timers", words: words)
    }

    @Test("One running timer is one activity with the timer's start and end, amber, priority 15")
    func running() throws {
        var board = TimerBoard()
        board.startLength(300, label: "", now: t, id: id(1))
        let list = activities(board)
        #expect(list.count == 1)
        let activity = try #require(list.first)
        #expect(activity.id == id(1).uuidString)
        #expect(activity.moduleID == "timers")
        #expect(activity.key == "timers/\(id(1).uuidString)")
        #expect(activity.kind == .timer)
        #expect(activity.symbol == "timer")
        #expect(activity.title == "Timer")
        #expect(activity.startedAt == t)
        #expect(activity.endsAt == t.addingTimeInterval(300))
        #expect(activity.finishedAt == nil)
        #expect(activity.progress == nil)
        #expect(activity.priority == 15)
        #expect(activity.tint == .amber)
        #expect(activity.compactValue == nil)
        #expect(activity.detail == nil)
    }

    @Test("A finished timer is one activity with its finish date, titled and worded Done")
    func finished() throws {
        var board = TimerBoard()
        board.startLength(10, label: "", now: t, id: id(1))
        let finishedAt = t.addingTimeInterval(10)
        _ = board.collectFinished(now: finishedAt)
        let activity = try #require(activities(board).first)
        #expect(activities(board).count == 1)
        #expect(activity.finishedAt == finishedAt)
        #expect(activity.title == "Done")
        #expect(activity.compactValue == "Done")
        #expect(activity.symbol == "timer")
        #expect(activity.priority == 15)
        #expect(activity.tint == .amber)
        // The board of the hub keeps it for five seconds and then drops it.
        let live = HubActivityBoard.board(activities(board), now: finishedAt.addingTimeInterval(1))
        #expect(live.compact?.id == id(1).uuidString)
        let gone = HubActivityBoard.board(activities(board), now: finishedAt.addingTimeInterval(HubActivityBoard.finishedHold))
        #expect(gone.compact == nil)
    }

    @Test("A paused timer, a counting stopwatch and a halted stopwatch are no activity")
    func notLive() {
        var board = TimerBoard()
        board.startLength(300, label: "", now: t, id: id(1))
        board.startStopwatch(label: "", now: t, id: id(2))
        board.startStopwatch(label: "", now: t, id: id(3))
        let pausedTimer = board.pause(id(1), now: t.addingTimeInterval(5))
        let haltedWatch = board.pause(id(3), now: t.addingTimeInterval(5))
        #expect(pausedTimer)
        #expect(haltedWatch)
        #expect(activities(board).isEmpty)
    }

    @Test("The label reaches only the detail, never the title, the symbol or the short word")
    func labelOnlyInDetail() throws {
        var board = TimerBoard()
        board.startLength(300, label: "secret", now: t, id: id(1))
        board.startLength(5, label: "secret", now: t, id: id(2))
        _ = board.collectFinished(now: t.addingTimeInterval(5))
        let list = activities(board)
        #expect(list.count == 2)
        for activity in list {
            #expect(activity.detail == "secret")
            #expect(!activity.title.contains("secret"))
            #expect(!activity.symbol.contains("secret"))
            #expect(activity.compactValue?.contains("secret") != true)
            #expect(!activity.id.contains("secret"))
            #expect(!activity.moduleID.contains("secret"))
        }
        // The rule of the live state therefore cannot draw it either.
        let content = HubLiveState.make(board: HubActivityBoard.board(list, now: t.addingTimeInterval(1)), now: t.addingTimeInterval(1))
        #expect(!String(describing: content).contains("secret"))
    }

    @Test("The same timer gives the same id on every call, an empty board none, and eight timers eight")
    func ids() {
        var board = TimerBoard()
        #expect(activities(board).isEmpty)
        for number in 1...8 {
            board.startLength(300, label: "", now: t, id: id(number))
        }
        let first = activities(board)
        #expect(first.count == 8)
        #expect(first.map(\.id) == activities(board).map(\.id))
        #expect(first.map(\.id) == (1...8).map { id($0).uuidString })
    }

    @Test("A timer that ends after the moment counts down, and the live state says so")
    func countdownThroughTheRule() throws {
        var board = TimerBoard()
        board.startLength(300, label: "", now: t, id: id(1))
        let live = HubActivityBoard.board(activities(board), now: t.addingTimeInterval(60))
        let content = try #require(HubLiveState.make(board: live, now: t.addingTimeInterval(60)))
        #expect(content.trailing == .countdown(end: t.addingTimeInterval(300)))
        #expect(content.symbol == "timer")
        #expect(content.tint == .amber)
    }
}
