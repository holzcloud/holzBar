import Testing
@testable import HolzBarCore

@Suite("SystemActivity")
struct SystemActivityTests {
    // The state is changed outside `#expect`, whose expansion cannot call a mutating method.

    private let start = ContinuousClock.now

    @Test("Locking pauses")
    func lockingPauses() {
        var activity = SystemActivity()
        activity.handle(.screenLocked, at: start)
        #expect(activity.isPaused)
        #expect(!activity.settled(at: start + .seconds(10)))
    }

    @Test("Unlocking settles first")
    func unlockingSettlesFirst() {
        var activity = SystemActivity()
        activity.handle(.screenLocked, at: start)
        let unlockedAt = start + .seconds(30)
        activity.handle(.screenUnlocked, at: unlockedAt)
        #expect(!activity.isPaused)
        #expect(!activity.settled(at: unlockedAt + .seconds(1)))
        #expect(activity.settled(at: unlockedAt + .seconds(2)))
    }

    @Test("Sleep and a switched-away session pause until both end")
    func sleepAndSessionPauseUntilBothEnd() {
        var activity = SystemActivity()
        activity.handle(.willSleep, at: start)
        activity.handle(.sessionResigned, at: start + .seconds(1))
        activity.handle(.didWake, at: start + .seconds(60))
        #expect(activity.isPaused)
        #expect(!activity.settled(at: start + .seconds(120)))
        let backAt = start + .seconds(90)
        activity.handle(.sessionBecameActive, at: backAt)
        #expect(!activity.isPaused)
        #expect(activity.settled(at: backAt + SystemActivity.settleDelay))
    }

    @Test("A display change only settles")
    func displayChangeOnlySettles() {
        var activity = SystemActivity()
        activity.handle(.displaysChanged, at: start)
        #expect(!activity.isPaused)
        #expect(!activity.settled(at: start + .seconds(1)))
        #expect(activity.settled(at: start + .seconds(2)))
    }

    @Test("Without any event holzBar is settled")
    func settledWithoutEvents() {
        let activity = SystemActivity()
        #expect(!activity.isPaused)
        #expect(activity.settled(at: start))
    }
}
