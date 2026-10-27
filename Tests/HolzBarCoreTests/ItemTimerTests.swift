import Foundation
import Testing
@testable import HolzBarCore

@Suite("ItemTimer")
struct ItemTimerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Lengths are kept between one minute and one hour")
    func clamping() {
        #expect(ItemTimer.clampedMinutes(0) == 1)
        #expect(ItemTimer.clampedMinutes(-5) == 1)
        #expect(ItemTimer.clampedMinutes(25) == 25)
        #expect(ItemTimer.clampedMinutes(61) == 60)
        #expect(ItemTimer.minuteChoices.contains(ItemTimer.defaultMinutes))
        #expect(ItemTimer.minuteChoices.allSatisfy { ItemTimer.clampedMinutes($0) == $0 })
    }

    @Test("Seconds are written as m:ss")
    func format() {
        #expect(ItemTimer.format(seconds: 0) == "0:00")
        #expect(ItemTimer.format(seconds: 9) == "0:09")
        #expect(ItemTimer.format(seconds: 61) == "1:01")
        #expect(ItemTimer.format(seconds: 300) == "5:00")
        #expect(ItemTimer.format(seconds: 3_600) == "60:00")
        #expect(ItemTimer.format(seconds: -4) == "0:00")
    }

    @Test("An idle timer shows its length and nothing wakes it")
    func idle() {
        let timer = ItemTimer()
        #expect(timer.label(minutes: 5, now: start) == "5:00")
        #expect(timer.label(minutes: 500, now: start) == "60:00")
        #expect(!timer.isRunning)
        #expect(timer.nextWake(now: start, isSeen: true) == nil)
    }

    @Test("A click starts it, the next click cancels it")
    func tap() {
        var timer = ItemTimer()
        timer.tap(minutes: 2, now: start)
        #expect(timer.isRunning)
        #expect(timer.phase == .running(endsAt: start.addingTimeInterval(120)))
        timer.tap(minutes: 2, now: start.addingTimeInterval(10))
        #expect(timer.phase == .idle)
    }

    @Test("It counts down, rounding up, and finishes once")
    func countdown() {
        var timer = ItemTimer()
        timer.tap(minutes: 1, now: start)
        #expect(timer.label(minutes: 1, now: start) == "1:00")
        #expect(timer.label(minutes: 1, now: start.addingTimeInterval(0.4)) == "1:00")
        #expect(timer.label(minutes: 1, now: start.addingTimeInterval(1)) == "0:59")
        #expect(timer.label(minutes: 1, now: start.addingTimeInterval(59.2)) == "0:01")
        let early = timer.advance(now: start.addingTimeInterval(59.9))
        #expect(!early)
        let atTheEnd = timer.advance(now: start.addingTimeInterval(60))
        #expect(atTheEnd)
        #expect(timer.phase == .finished)
        let again = timer.advance(now: start.addingTimeInterval(61))
        #expect(!again)
        #expect(timer.label(minutes: 1, now: start.addingTimeInterval(61)) == "0:00")
        #expect(timer.nextWake(now: start.addingTimeInterval(61), isSeen: true) == nil)
        timer.tap(minutes: 1, now: start.addingTimeInterval(70))
        #expect(timer.phase == .idle)
    }

    @Test("A seen timer wakes when the text changes, an unseen one only at the end")
    func wake() {
        var timer = ItemTimer()
        timer.tap(minutes: 1, now: start)
        let end = start.addingTimeInterval(60)
        // 59.7 s left: the text shows 1:00 and becomes 0:59 when 59 s are left, 0.7 s from now.
        let first = start.addingTimeInterval(0.3)
        #expect(timer.nextWake(now: first, isSeen: true) == end.addingTimeInterval(-59))
        // Exactly 5 s left: the text shows 0:05 and becomes 0:04 a second later.
        let five = start.addingTimeInterval(55)
        #expect(timer.nextWake(now: five, isSeen: true) == end.addingTimeInterval(-4))
        // The last second wakes at the end.
        #expect(timer.nextWake(now: start.addingTimeInterval(59.5), isSeen: true) == end)
        #expect(timer.nextWake(now: start.addingTimeInterval(30), isSeen: false) == end)
    }

    @Test("Waking at the given moments shows every second once, in order")
    func walk() {
        var timer = ItemTimer()
        timer.tap(minutes: 1, now: start.addingTimeInterval(0.25))
        var now = start.addingTimeInterval(0.25)
        var shown = [String]()
        var steps = 0
        while let wake = timer.nextWake(now: now, isSeen: true), steps < 200 {
            shown.append(timer.label(minutes: 1, now: now))
            now = wake
            _ = timer.advance(now: now)
            steps += 1
        }
        shown.append(timer.label(minutes: 1, now: now))
        #expect(shown.first == "1:00")
        #expect(shown.last == "0:00")
        #expect(shown.count == 61)
        #expect(Set(shown).count == shown.count)
    }
}
