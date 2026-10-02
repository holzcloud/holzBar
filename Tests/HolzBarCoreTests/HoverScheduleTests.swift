import Testing
@testable import HolzBarCore

@Suite("HoverSchedule")
struct HoverScheduleTests {
    private enum Action {
        case show
        case hide
    }

    @Test("The first request starts an action")
    func firstRequestStartsAnAction() {
        var schedule = HoverSchedule<Action>()
        #expect(schedule.request(.show) != nil)
        #expect(schedule.pending == .show)
    }

    @Test("A second request for the same action starts nothing")
    func secondRequestForTheSameActionStartsNothing() {
        var schedule = HoverSchedule<Action>()
        _ = schedule.request(.show)
        #expect(schedule.request(.show) == nil)
        #expect(schedule.pending == .show)
    }

    @Test("A different action replaces the pending one")
    func differentActionReplacesThePendingOne() throws {
        var schedule = HoverSchedule<Action>()
        let first = try #require(schedule.request(.show))
        let second = try #require(schedule.request(.hide))
        #expect(second > first)
        #expect(schedule.pending == .hide)
    }

    @Test("Finishing the current action allows the next one")
    func finishingTheCurrentActionAllowsTheNextOne() throws {
        var schedule = HoverSchedule<Action>()
        let generation = try #require(schedule.request(.show))
        schedule.finish(generation)
        #expect(schedule.pending == nil)
        #expect(schedule.request(.show) != nil)
    }

    @Test("Finishing an older action changes nothing")
    func finishingAnOlderActionChangesNothing() throws {
        var schedule = HoverSchedule<Action>()
        let older = try #require(schedule.request(.show))
        _ = try #require(schedule.request(.hide))
        schedule.finish(older)
        #expect(schedule.pending == .hide)
    }
}
