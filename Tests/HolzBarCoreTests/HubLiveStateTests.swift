import Foundation
import Testing
@testable import HolzBarCore

@Suite("HubLiveState")
struct HubLiveStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func activity(
        _ id: String,
        title: String = "A title",
        detail: String? = nil,
        symbol: String = "star",
        progress: Double? = nil,
        priority: Int = 10,
        started: TimeInterval = 0,
        ends: TimeInterval? = nil,
        finished: TimeInterval? = nil,
        tint: LiveActivityTint = .accent,
        compactValue: String? = nil,
        flash: LiveActivityFlash? = nil
    ) -> LiveActivity {
        LiveActivity(
            id: id,
            moduleID: "live-activities",
            kind: .other,
            symbol: symbol,
            title: title,
            detail: detail,
            progress: progress,
            priority: priority,
            startedAt: now.addingTimeInterval(started),
            endsAt: ends.map { now.addingTimeInterval($0) },
            finishedAt: finished.map { now.addingTimeInterval($0) },
            tint: tint,
            compactValue: compactValue,
            flash: flash
        )
    }

    private func content(_ activities: [LiveActivity], after seconds: TimeInterval = 0) -> HubLiveState.Content? {
        let moment = now.addingTimeInterval(seconds)
        return HubLiveState.make(board: HubActivityBoard.board(activities, now: moment, forClosedNotch: true), now: moment)
    }

    @Test("An empty board gives no content")
    func emptyBoard() {
        #expect(content([]) == nil)
    }

    @Test("A running activity that ends after now gives its countdown; one whose end has passed does not")
    func countdown() throws {
        let running = try #require(content([activity("timer", ends: 300)]))
        #expect(running.trailing == .countdown(end: now.addingTimeInterval(300)))
        let overdue = try #require(content([activity("late", ends: -2, compactValue: "Camera")]))
        #expect(overdue.trailing == .word("Camera"))
        let overdueNothing = try #require(content([activity("late", ends: -2)]))
        #expect(overdueNothing.trailing == HubLiveState.Trailing.none)
    }

    @Test("The countdown wins over a percentage and a word")
    func countdownFirst() throws {
        let value = try #require(content([activity("both", progress: 0.5, ends: 60, compactValue: "Download")]))
        #expect(value.trailing == .countdown(end: now.addingTimeInterval(60)))
    }

    @Test("A percentage is the progress rounded to a whole number, and wins over a word")
    func percentage() throws {
        let value = try #require(content([activity("download", progress: 0.64, compactValue: "Download")]))
        #expect(value.trailing == .percent(64))
        let rounded = try #require(content([activity("download", progress: 0.665)]))
        #expect(rounded.trailing == .percent(67))
        let started = try #require(content([activity("download", progress: 0)]))
        #expect(started.trailing == .percent(0))
    }

    @Test("A finished activity shows its short word, a camera its word, and one with nothing to say shows none")
    func words() throws {
        let done = try #require(content([activity("done", progress: 1, finished: -1, compactValue: "Done")]))
        #expect(done.trailing == .word("Done"))
        let camera = try #require(content([activity("camera", compactValue: "Camera")]))
        #expect(camera.trailing == .word("Camera"))
        let silent = try #require(content([activity("silent")]))
        #expect(silent.trailing == HubLiveState.Trailing.none)
        let blank = try #require(content([activity("blank", compactValue: "  ")]))
        #expect(blank.trailing == HubLiveState.Trailing.none)
    }

    @Test("The symbol and the tint are the top activity's, and the extra count is the board's hidden count")
    func topActivity() throws {
        let value = try #require(
            content([
                activity("low", symbol: "bolt", priority: 10, tint: .green),
                activity("top", symbol: "battery.25", priority: 30, tint: .red),
                activity("mid", symbol: "camera", priority: 20, tint: .amber),
            ])
        )
        #expect(value.symbol == "battery.25")
        #expect(value.tint == .red)
        #expect(value.extraCount == 2)
        let single = try #require(content([activity("only")]))
        #expect(single.extraCount == 0)
    }

    @Test("A title, a detail or a name never reaches the content")
    func privacy() throws {
        let value = try #require(
            content([
                activity(
                    "x1",
                    title: "Holz's AirPods connected",
                    detail: "secret.pdf",
                    symbol: "airpods",
                    compactValue: "Connected"
                )
            ])
        )
        let rendered = String(describing: value)
        #expect(!rendered.contains("AirPods"))
        #expect(!rendered.contains("secret"))
        #expect(value.trailing == .word("Connected"))
    }

    @Test("The short word is capped at 16 characters and is nil by default")
    func compactValueCap() {
        let plain = activity("plain")
        #expect(plain.compactValue == nil)
        #expect(LiveActivity.maximumCompactValueLength == 16)
        let long = activity("long", compactValue: String(repeating: "x", count: 40))
        #expect(long.compactValue?.count == 16)
        let short = activity("short", compactValue: "Camera")
        #expect(short.compactValue == "Camera")
    }

    // MARK: Flashes and a finish that lies ahead (D-09, D-24)

    @Test("A finished flash carries its second text and icon with its word")
    func flashWord() throws {
        let icon = URL(string: "file:///Library/Icons/de.png")
        let flash = LiveActivityFlash(secondaryValue: "German", symbolImageURL: icon)
        let value = try #require(content([activity("flash", finished: 0, compactValue: "DE", flash: flash)]))
        #expect(value.trailing == .word("DE"))
        #expect(value.secondary == "German")
        #expect(value.symbolImageURL == icon)
        let plain = try #require(content([activity("plain", finished: 0, compactValue: "DE")]))
        #expect(plain.secondary == nil)
        #expect(plain.symbolImageURL == nil)
    }

    @Test("A flash without a word carries no second text, and a running countdown never does")
    func flashWithoutAWord() throws {
        let flash = LiveActivityFlash(secondaryValue: "German", symbolImageURL: URL(string: "file:///a.png"))
        let none = try #require(content([activity("flash", finished: 0, flash: flash)]))
        #expect(none.trailing == HubLiveState.Trailing.none)
        #expect(none.secondary == nil)
        #expect(none.symbolImageURL == nil)
        let countdown = try #require(content([activity("timer", ends: 60, compactValue: "DE", flash: flash)]))
        #expect(countdown.trailing == .countdown(end: now.addingTimeInterval(60)))
        #expect(countdown.secondary == nil)
        #expect(countdown.symbolImageURL == nil)
    }

    @Test("An activity whose finish lies ahead keeps its countdown or percentage until the finish")
    func finishAhead() throws {
        let meeting = activity("meeting", ends: 60, finished: 60, compactValue: "Now")
        let before = try #require(content([meeting]))
        #expect(before.trailing == .countdown(end: now.addingTimeInterval(60)))
        let atEnd = try #require(content([meeting], after: 60))
        #expect(atEnd.trailing == .word("Now"))
        let bare = activity("bare", ends: 60, finished: 60)
        let atEndBare = try #require(content([bare], after: 60))
        #expect(atEndBare.trailing == HubLiveState.Trailing.none)
        let percent = try #require(content([activity("download", progress: 0.4, finished: 30)]))
        #expect(percent.trailing == .percent(40))
        let finished = try #require(content([activity("download", progress: 0.4, finished: -1)]))
        #expect(finished.trailing == HubLiveState.Trailing.none)
    }
}
