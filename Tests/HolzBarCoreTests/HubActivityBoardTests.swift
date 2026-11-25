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
        finished: TimeInterval? = nil,
        widened: TimeInterval? = nil,
        hold: TimeInterval? = nil,
        flash: LiveActivityFlash? = nil
    ) -> LiveActivity {
        LiveActivity(
            id: id,
            moduleID: module,
            kind: .other,
            symbol: "star",
            title: id,
            priority: priority,
            startedAt: now.addingTimeInterval(started),
            finishedAt: finished.map { now.addingTimeInterval($0) },
            widenedSeconds: widened,
            holdSeconds: hold,
            flash: flash
        )
    }

    /// An alert: it widens the closed notch for 30 seconds from its start.
    private func alert(
        _ id: String,
        priority: Int = 30,
        started: TimeInterval = 0,
        finished: TimeInterval? = nil
    ) -> LiveActivity {
        activity(id, module: "system-alerts", priority: priority, started: started, finished: finished, widened: 30)
    }

    private func at(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(seconds)
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

    // MARK: The closed notch's view (D-19, UI-SPEC A2)

    @Test("The closed view widens for the activity's widening seconds and then drops it")
    func closedViewDropsAWidenedActivity() {
        let alerts = [alert("cpu")]
        let before = Board.board(alerts, now: at(29), forClosedNotch: true)
        #expect(before.compact?.id == "cpu")
        let after = Board.board(alerts, now: at(30), forClosedNotch: true)
        #expect(after.compact == nil)
        #expect(after.listed.isEmpty)
        #expect(after.hiddenCount == 0)
        // The full view, the open hub's and the Live activities list's, keeps it.
        let full = Board.board(alerts, now: at(30))
        #expect(full.compact?.id == "cpu")
        #expect(full.listed.map(\.id) == ["cpu"])
    }

    @Test("A widened activity past its widening is not counted as hidden in the closed view")
    func closedViewDoesNotCountAWidenedActivity() {
        let activities = [alert("cpu", priority: 30), activity("camera", priority: 20)]
        let closed = Board.board(activities, now: at(31), forClosedNotch: true)
        #expect(closed.compact?.id == "camera")
        #expect(closed.hiddenCount == 0)
        let full = Board.board(activities, now: at(31))
        #expect(full.compact?.id == "cpu")
        #expect(full.hiddenCount == 1)
    }

    @Test("The next expiry is the end of a widening in both views, or an earlier leave")
    func nextExpiryCoversTheWidening() {
        let alerts = [alert("cpu")]
        #expect(Board.board(alerts, now: at(10)).nextExpiry == at(30))
        #expect(Board.board(alerts, now: at(10), forClosedNotch: true).nextExpiry == at(30))
        let withFinished = alerts + [activity("done", started: 0, finished: 15)]
        #expect(Board.board(withFinished, now: at(10)).nextExpiry == at(20))
        #expect(Board.board(withFinished, now: at(10), forClosedNotch: true).nextExpiry == at(20))
    }

    @Test("A recovery has its own id, key, look and widening from the moment of recovery")
    func recoveryLook() {
        #expect(AlertLook.recoveredID(of: .thermal) == "thermal.recovered")
        let cpu = AlertLook.recovery(of: .cpu, title: "CPU load back to normal", compactValue: "Normal", at: at(600))
        #expect(cpu.id == "cpu.recovered")
        #expect(cpu.key == "system-alerts/cpu.recovered")
        #expect(cpu.symbol == "checkmark.circle")
        #expect(cpu.tint == .green)
        #expect(cpu.priority == 25)
        #expect(cpu.startedAt == at(600))
        #expect(cpu.finishedAt == at(600))
        #expect(cpu.widenedSeconds == DesignTokens.Alert.widenedSeconds)
        #expect(!cpu.announcesItself)
        #expect(cpu.compactValue == "Normal")
        let thermal = AlertLook.recovery(of: .thermal, title: "Thermal state back to normal", compactValue: "Normal", at: at(1))
        #expect(thermal.priority == 30)
    }

    @Test("The recovery after a long alert shows in the closed notch for its five seconds")
    func recoveryAfterALongAlertWidensTheClosedNotch() {
        let recovery = AlertLook.recovery(of: .cpu, title: "CPU", compactValue: "Normal", at: at(600))
        for seconds in [600.0, 604.9] {
            let closed = Board.board([recovery], now: at(seconds), forClosedNotch: true)
            #expect(closed.compact?.id == "cpu.recovered")
        }
        let closedAfter = Board.board([recovery], now: at(605), forClosedNotch: true)
        #expect(closedAfter.compact == nil)
        #expect(closedAfter.listed.isEmpty)
        let fullAfter = Board.board([recovery], now: at(605))
        #expect(fullAfter.compact == nil)
        #expect(fullAfter.listed.isEmpty)
        #expect(Board.board([recovery], now: at(600), forClosedNotch: true).nextExpiry == at(605))
        #expect(Board.board([recovery], now: at(600)).nextExpiry == at(605))
    }

    @Test("A recovery inside the first seconds behaves the same")
    func recoveryInsideTheFirstSeconds() {
        let recovery = AlertLook.recovery(of: .cpu, title: "CPU", compactValue: "Normal", at: at(10))
        #expect(Board.board([recovery], now: at(10), forClosedNotch: true).compact?.id == "cpu.recovered")
        #expect(Board.board([recovery], now: at(15), forClosedNotch: true).compact == nil)
    }

    @Test("A recovery goes before a still widened alert of its priority, a lower priority recovery after a thermal one")
    func recoveryOrdering() {
        let firing = alert("cpu", priority: 25)
        let memory = AlertLook.recovery(of: .memoryPressure, title: "Memory", compactValue: "Normal", at: at(20))
        let atTwenty = Board.board([firing, memory], now: at(20), forClosedNotch: true)
        #expect(atTwenty.compact?.id == "memoryPressure.recovered")
        #expect(atTwenty.hiddenCount == 1)
        let atTwentyFive = Board.board([firing, memory], now: at(25), forClosedNotch: true)
        #expect(atTwentyFive.compact?.id == "cpu")

        let thermal = alert("thermal", priority: 30)
        let cpu = AlertLook.recovery(of: .cpu, title: "CPU", compactValue: "Normal", at: at(600))
        let closed = Board.board([thermal, cpu], now: at(600), forClosedNotch: true)
        #expect(closed.compact?.id == "cpu.recovered")
        let full = Board.board([thermal, cpu], now: at(600))
        #expect(full.compact?.id == "thermal")
    }

    @Test("An activity without widening seconds behaves the same in both views")
    func noWideningMeansAsLongAsItRuns() {
        let activities = [activity("capture", priority: 20, started: -7_200), activity("timer", priority: 10)]
        let full = Board.board(activities, now: now)
        let closed = Board.board(activities, now: now, forClosedNotch: true)
        #expect(closed == full)
        #expect(Board.board(activities, now: at(86_400), forClosedNotch: true).compact?.id == "capture")
    }

    @Test("A widening that is negative or not a number is dropped")
    func invalidWideningIsNil() {
        func make(_ seconds: TimeInterval?) -> LiveActivity {
            activity("x", widened: seconds)
        }
        #expect(make(-1).widenedSeconds == nil)
        #expect(make(.nan).widenedSeconds == nil)
        #expect(make(.infinity).widenedSeconds == nil)
        #expect(make(30).widenedSeconds == 30)
        #expect(make(nil).widenedSeconds == nil)
        #expect(make(30).widenedUntil == at(30))
        #expect(make(nil).widenedUntil == nil)
    }

    // MARK: The hold of a finished activity (D-08)

    @Test("A finished activity with a hold of 1.5 seconds is on the board at 1.4 and gone at 1.5")
    func holdOfOneAndAHalfSeconds() {
        let held = activity("a", finished: 0, hold: 1.5)
        #expect(Board.board([held], now: at(1.4)).compact?.id == "a")
        #expect(Board.board([held], now: at(1.5)).compact == nil)
        #expect(Board.board([held], now: at(1.5)).listed.isEmpty)
        #expect(Board.board([held], now: at(0)).nextExpiry == at(1.5))
        #expect(held.expiresAt == at(1.5))
    }

    @Test("A finished activity without a hold still leaves after five seconds")
    func noHoldKeepsTheDefault() {
        let plain = activity("a", finished: 0)
        #expect(plain.holdSeconds == nil)
        #expect(plain.expiresAt == at(5))
        #expect(Board.board([plain], now: at(4.9)).compact?.id == "a")
        #expect(Board.board([plain], now: at(5)).compact == nil)
        #expect(Board.board([plain], now: at(0)).nextExpiry == at(5))
    }

    @Test("A hold that is negative or not a number is stored as nil, a hold of zero stays")
    func invalidHoldIsNil() {
        #expect(activity("a", finished: 0, hold: -1).holdSeconds == nil)
        #expect(activity("a", finished: 0, hold: .infinity).holdSeconds == nil)
        #expect(activity("a", finished: 0, hold: .nan).holdSeconds == nil)
        #expect(activity("a", finished: 0, hold: 0).holdSeconds == 0)
        #expect(activity("a", finished: 0, hold: 2).holdSeconds == 2)
        #expect(activity("a", finished: 0, hold: -1).expiresAt == at(5))
    }

    @Test("A running activity has no expiry")
    func runningHasNoExpiry() {
        #expect(activity("a").expiresAt == nil)
        #expect(activity("a", hold: 3).expiresAt == nil)
    }

    @Test("A hold of zero ends the activity exactly at its finish, also when that lies ahead")
    func zeroHoldEndsAtTheFinish() {
        let countdown = activity("meeting", finished: 60, hold: 0)
        #expect(countdown.expiresAt == at(60))
        let before = Board.board([countdown], now: at(59))
        #expect(before.compact?.id == "meeting")
        #expect(before.nextExpiry == at(60))
        let atEnd = Board.board([countdown], now: at(60))
        #expect(atEnd.compact == nil)
        #expect(atEnd.listed.isEmpty)
        #expect(atEnd.nextExpiry == nil)
    }

    @Test("The next expiry takes each activity's own hold")
    func nextExpiryTakesTheOwnHold() {
        let board = Board.board(
            [activity("short", finished: -1, hold: 2), activity("default", finished: -1)],
            now: now
        )
        #expect(board.nextExpiry == at(1))
        #expect(board.listed.count == 2)
    }

    // MARK: Flashes (D-09)

    @Test("A flash is drawn by the closed notch only: the full view lists, counts and waits for none")
    func flashIsClosedNotchOnly() {
        let flash = activity("flash", priority: 40, finished: 0, hold: 1.5, flash: LiveActivityFlash(secondaryValue: "German"))
        let plain = activity("plain", priority: 30)
        #expect(flash.isFlash)
        #expect(!plain.isFlash)
        let closed = Board.board([plain, flash], now: at(0.5), forClosedNotch: true)
        #expect(closed.listed.map(\.id) == ["flash", "plain"])
        #expect(closed.compact?.id == "flash")
        #expect(closed.hiddenCount == 1)
        #expect(closed.nextExpiry == at(1.5))
        let full = Board.board([plain, flash], now: at(0.5))
        #expect(full.listed.map(\.id) == ["plain"])
        #expect(full.compact?.id == "plain")
        #expect(full.hiddenCount == 0)
        #expect(full.nextExpiry == nil)
        let onlyFlash = Board.board([flash], now: at(0.5))
        #expect(onlyFlash.compact == nil)
        #expect(onlyFlash.listed.isEmpty)
        #expect(Board.board([flash], now: at(1.5), forClosedNotch: true).compact == nil)
    }

    @Test("A flash is cut to short text, file URLs and a short width sample")
    func flashCaps() {
        let long = LiveActivityFlash(
            secondaryValue: String(repeating: "s", count: 40),
            symbolImageURL: URL(string: "file:///Library/Icons/de.png"),
            widthSample: String(repeating: "w", count: 20)
        )
        #expect(LiveActivityFlash.maximumSecondaryLength == 32)
        #expect(LiveActivityFlash.maximumSampleLength == 16)
        #expect(long.secondaryValue?.count == 32)
        #expect(long.widthSample?.count == 16)
        #expect(long.symbolImageURL?.isFileURL == true)
        let remote = LiveActivityFlash(symbolImageURL: URL(string: "https://example.com/icon.png"))
        #expect(remote.symbolImageURL == nil)
        let web = LiveActivityFlash(symbolImageURL: URL(string: "http://example.com/icon.png"))
        #expect(web.symbolImageURL == nil)
        let empty = LiveActivityFlash()
        #expect(empty.secondaryValue == nil)
        #expect(empty.widthSample == nil)
        #expect(empty.symbolImageURL == nil)
    }
}
