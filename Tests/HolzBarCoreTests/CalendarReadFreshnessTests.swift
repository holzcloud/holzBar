import Foundation
import Testing
@testable import HolzBarCore

@Suite("CalendarReadFreshness")
struct CalendarReadFreshnessTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Nothing read yet: the rows do not decide")
    func neverRead() {
        let freshness = CalendarReadFreshness()
        #expect(!freshness.mayDecide(now: start))
    }

    @Test("A read decides at the next opening while nothing says it is out of date")
    func readDecides() {
        var freshness = CalendarReadFreshness()
        freshness.didRead(startedAt: start, token: freshness.token)
        #expect(freshness.mayDecide(now: start.addingTimeInterval(5)))
        #expect(freshness.mayDecide(now: start.addingTimeInterval(CalendarReadFreshness.maximumAge)))
    }

    @Test("A read older than the maximum age does not decide")
    func tooOld() {
        var freshness = CalendarReadFreshness()
        freshness.didRead(startedAt: start, token: freshness.token)
        #expect(!freshness.mayDecide(now: start.addingTimeInterval(CalendarReadFreshness.maximumAge + 1)))
        #expect(CalendarReadFreshness.maximumAge == 1800)
    }

    @Test("A clock set back leaves a read from the future that does not decide")
    func fromTheFuture() {
        var freshness = CalendarReadFreshness()
        freshness.didRead(startedAt: start, token: freshness.token)
        #expect(!freshness.mayDecide(now: start.addingTimeInterval(-1)))
    }

    @Test("A change of the store or the settings makes the rows not decide, until a new read")
    func changeInvalidates() {
        var freshness = CalendarReadFreshness()
        freshness.didRead(startedAt: start, token: freshness.token)
        freshness.didChange()
        #expect(!freshness.mayDecide(now: start.addingTimeInterval(1)))
        freshness.didRead(startedAt: start.addingTimeInterval(10), token: freshness.token)
        #expect(freshness.mayDecide(now: start.addingTimeInterval(11)))
    }

    @Test("A read that started before a change and ended after it is not believed")
    func readOverlappingAChange() {
        var freshness = CalendarReadFreshness()
        freshness.didRead(startedAt: start, token: freshness.token)
        let token = freshness.token
        freshness.didChange()
        freshness.didRead(startedAt: start.addingTimeInterval(1), token: token)
        #expect(!freshness.mayDecide(now: start.addingTimeInterval(2)))
        #expect(freshness.readAt == nil)
    }

    @Test("A reset holds nothing, and it also refuses a read that was already under way")
    func resetHoldsNothing() {
        var freshness = CalendarReadFreshness()
        let token = freshness.token
        freshness.didRead(startedAt: start, token: token)
        freshness.reset()
        #expect(!freshness.mayDecide(now: start))
        freshness.didRead(startedAt: start, token: token)
        #expect(!freshness.mayDecide(now: start))
    }

    @Test("Used with the context: a deleted meeting no longer decides, a still-valid one does, one out of the window never")
    func withTheContext() {
        let now = start.addingTimeInterval(120)
        func decision(_ meeting: HubContext.Meeting, _ freshness: CalendarReadFreshness) -> HubContext.Decision {
            let signal = HubContext.Signal.meetings(freshness.mayDecide(now: now) ? [meeting] : [])
            return HubContext.decide(
                HubContext.Inputs(
                    now: now,
                    moduleTabs: ["calendar"],
                    signals: [HubContext.ModuleSignal(moduleID: "calendar", signal: signal)],
                    liveOwner: nil,
                    lastChosen: nil,
                    showsActiveFirst: true
                )
            )
        }
        var freshness = CalendarReadFreshness()
        freshness.didRead(startedAt: start, token: freshness.token)
        let soon = HubContext.Meeting(start: now.addingTimeInterval(10 * 60), end: now.addingTimeInterval(40 * 60))
        let running = HubContext.Meeting(start: now.addingTimeInterval(-5 * 60), end: now.addingTimeInterval(25 * 60))
        let far = HubContext.Meeting(start: now.addingTimeInterval(20 * 60), end: now.addingTimeInterval(50 * 60))
        let ended = HubContext.Meeting(start: now.addingTimeInterval(-50 * 60), end: now.addingTimeInterval(-20 * 60))
        #expect(decision(soon, freshness) == HubContext.Decision(moduleID: "calendar", reason: .meetingSoon))
        #expect(decision(running, freshness) == HubContext.Decision(moduleID: "calendar", reason: .meetingNow))
        // Believed rows still obey the clock: a meeting beyond the lead or already over never decides.
        #expect(decision(far, freshness).reason == .overview)
        #expect(decision(ended, freshness).reason == .overview)
        // The event was deleted or moved: the store reported it, so the rows no longer decide.
        freshness.didChange()
        #expect(decision(soon, freshness).reason == .overview)
        #expect(decision(running, freshness).reason == .overview)
    }
}
