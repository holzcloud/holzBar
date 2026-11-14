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
        compactValue: String? = nil
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
            compactValue: compactValue
        )
    }

    private func content(_ activities: [LiveActivity]) -> HubLiveState.Content? {
        HubLiveState.make(board: HubActivityBoard.board(activities, now: now), now: now)
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
}
