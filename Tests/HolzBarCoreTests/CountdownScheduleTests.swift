import Foundation
import Testing
@testable import HolzBarCore

@Suite("Countdown schedule")
struct CountdownScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The lead's raw values are minutes, appended only, and the default is five minutes")
    func leadRawValues() {
        #expect(CountdownLead.allCases.map(\.rawValue) == [0, 1, 5, 10, 15])
        #expect(CountdownLead.defaultLead == .fiveMinutes)
        #expect(CountdownLead.off.seconds == nil)
        #expect(CountdownLead.oneMinute.seconds == 60)
        #expect(CountdownLead.fifteenMinutes.seconds == 900)
    }

    @Test("A stored lead snaps to the nearest choice, a tie to the shorter")
    func snapping() {
        #expect(CountdownLead.snapped(3) == .oneMinute)
        #expect(CountdownLead.snapped(4) == .fiveMinutes)
        #expect(CountdownLead.snapped(12) == .tenMinutes)
        #expect(CountdownLead.snapped(13) == .fifteenMinutes)
        #expect(CountdownLead.snapped(99) == .fifteenMinutes)
        #expect(CountdownLead.snapped(-2) == .off)
        #expect(CountdownLead.snapped(0) == .off)
        for lead in CountdownLead.allCases {
            #expect(CountdownLead.snapped(lead.rawValue) == lead)
        }
    }

    @Test("A start 600 s away with a five-minute lead plans the countdown at 300 s and amber at 540 s")
    func plan() throws {
        let start = now.addingTimeInterval(600)
        let plan = try #require(CountdownSchedule.plan(nextStart: start, lead: .fiveMinutes, now: now))
        #expect(plan.startsAt == now.addingTimeInterval(300))
        #expect(plan.amberAt == now.addingTimeInterval(540))
        #expect(plan.meetingStart == start)
    }

    @Test("The wakes come in order: the lead, then 60 s before the start, then none")
    func wakes() throws {
        let start = now.addingTimeInterval(600)
        let plan = try #require(CountdownSchedule.plan(nextStart: start, lead: .fiveMinutes, now: now))
        #expect(CountdownSchedule.nextWake(plan, now: now) == now.addingTimeInterval(300))
        #expect(CountdownSchedule.nextWake(plan, now: now.addingTimeInterval(300)) == now.addingTimeInterval(540))
        #expect(CountdownSchedule.nextWake(plan, now: now.addingTimeInterval(540)) == nil)
        #expect(CountdownSchedule.nextWake(plan, now: now.addingTimeInterval(599)) == nil)
    }

    @Test("Amber is false at 539 s and true at 540 s")
    func amberBoundary() throws {
        let start = now.addingTimeInterval(600)
        let plan = try #require(CountdownSchedule.plan(nextStart: start, lead: .fiveMinutes, now: now))
        #expect(!CountdownSchedule.isAmber(plan, now: now.addingTimeInterval(539)))
        #expect(CountdownSchedule.isAmber(plan, now: now.addingTimeInterval(540)))
    }

    @Test("A start inside the lead plans a countdown that shows at once, amber when within 60 s")
    func insideLead() throws {
        let plan = try #require(CountdownSchedule.plan(nextStart: now.addingTimeInterval(30), lead: .fiveMinutes, now: now))
        #expect(plan.startsAt < now)
        #expect(plan.amberAt < now)
        #expect(CountdownSchedule.isAmber(plan, now: now))
        #expect(CountdownSchedule.nextWake(plan, now: now) == nil)

        let calm = try #require(CountdownSchedule.plan(nextStart: now.addingTimeInterval(200), lead: .fiveMinutes, now: now))
        #expect(calm.startsAt < now)
        #expect(!CountdownSchedule.isAmber(calm, now: now))
        #expect(CountdownSchedule.nextWake(calm, now: now) == now.addingTimeInterval(140))
    }

    @Test("A lead of one minute has one wake, at the start of the amber minute")
    func oneMinuteLead() throws {
        let plan = try #require(CountdownSchedule.plan(nextStart: now.addingTimeInterval(600), lead: .oneMinute, now: now))
        #expect(plan.startsAt == plan.amberAt)
        #expect(CountdownSchedule.nextWake(plan, now: now) == now.addingTimeInterval(540))
        #expect(CountdownSchedule.nextWake(plan, now: now.addingTimeInterval(540)) == nil)
    }

    @Test("No plan with the lead off, no start, or a start at or before now")
    func noPlan() {
        #expect(CountdownSchedule.plan(nextStart: now.addingTimeInterval(600), lead: .off, now: now) == nil)
        #expect(CountdownSchedule.plan(nextStart: nil, lead: .fiveMinutes, now: now) == nil)
        #expect(CountdownSchedule.plan(nextStart: now, lead: .fiveMinutes, now: now) == nil)
        #expect(CountdownSchedule.plan(nextStart: now.addingTimeInterval(-5), lead: .fiveMinutes, now: now) == nil)
    }

    @Test("After the last wake of a meeting the next meeting's countdown start is the wake, not before the meeting starts")
    func followingWake() throws {
        let plan = try #require(CountdownSchedule.plan(nextStart: now.addingTimeInterval(600), lead: .fiveMinutes, now: now))
        let amberNow = now.addingTimeInterval(540)
        // A following meeting an hour away: its countdown starts five minutes before it.
        let later = now.addingTimeInterval(3600)
        #expect(CountdownSchedule.followingWake(after: plan, followingStart: later, lead: .fiveMinutes, now: amberNow)
            == later.addingTimeInterval(-300))
        // A back-to-back meeting: its countdown can start only when this one has.
        let backToBack = now.addingTimeInterval(660)
        #expect(CountdownSchedule.followingWake(after: plan, followingStart: backToBack, lead: .fiveMinutes, now: amberNow)
            == now.addingTimeInterval(600))
        // No following meeting, the same start, an earlier one or the lead off: no wake.
        #expect(CountdownSchedule.followingWake(after: plan, followingStart: nil, lead: .fiveMinutes, now: amberNow) == nil)
        #expect(CountdownSchedule.followingWake(after: plan, followingStart: plan.meetingStart, lead: .fiveMinutes, now: amberNow) == nil)
        #expect(CountdownSchedule.followingWake(after: plan, followingStart: later, lead: .off, now: amberNow) == nil)
    }

    @Test("The priority is 15, above the notification count and below a flash")
    func priority() {
        #expect(CountdownSchedule.priority == 15)
        #expect(CountdownSchedule.priority > DesignTokens.Indicator.notificationCountPriority)
        #expect(CountdownSchedule.priority < DesignTokens.Indicator.flashPriority)
        #expect(CountdownSchedule.amberLead == 60)
    }
}
