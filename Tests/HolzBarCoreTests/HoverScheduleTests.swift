import Testing
@testable import HolzBarCore

@Suite("HoverSchedule")
struct HoverScheduleTests {
    private enum Action {
        case show
        case hide
    }

    // The schedule is mutated outside `#expect` and `#require`, whose expansions cannot
    // call a mutating method.

    @Test("The first request starts an action")
    func firstRequestStartsAnAction() {
        var schedule = HoverSchedule<Action>()
        let generation = schedule.request(.show)
        #expect(generation != nil)
        #expect(schedule.pending == .show)
    }

    @Test("A second request for the same action starts nothing")
    func secondRequestForTheSameActionStartsNothing() {
        var schedule = HoverSchedule<Action>()
        _ = schedule.request(.show)
        let second = schedule.request(.show)
        #expect(second == nil)
        #expect(schedule.pending == .show)
    }

    @Test("A different action replaces the pending one")
    func differentActionReplacesThePendingOne() throws {
        var schedule = HoverSchedule<Action>()
        let showing = schedule.request(.show)
        let replacing = schedule.request(.hide)
        let first = try #require(showing)
        let second = try #require(replacing)
        #expect(second > first)
        #expect(schedule.pending == .hide)
    }

    @Test("Finishing the current action allows the next one")
    func finishingTheCurrentActionAllowsTheNextOne() throws {
        var schedule = HoverSchedule<Action>()
        let requested = schedule.request(.show)
        let generation = try #require(requested)
        schedule.finish(generation)
        #expect(schedule.pending == nil)
        let next = schedule.request(.show)
        #expect(next != nil)
    }

    @Test("Finishing an older action changes nothing")
    func finishingAnOlderActionChangesNothing() throws {
        var schedule = HoverSchedule<Action>()
        let requested = schedule.request(.show)
        let older = try #require(requested)
        _ = schedule.request(.hide)
        schedule.finish(older)
        #expect(schedule.pending == .hide)
    }
}
