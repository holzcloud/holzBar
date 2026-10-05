import Testing
@testable import HolzBarCore

@Suite("Event barrier policy")
struct EventBarrierPolicyTests {
    @Test("A main barrier waits at least the minimum")
    func mainWait() {
        #expect(EventBarrierPolicy.Bound.main.wait(timeout: .milliseconds(50), count: 1) == .milliseconds(500))
        #expect(EventBarrierPolicy.Bound.main.wait(timeout: .milliseconds(250), count: 2) == .milliseconds(500))
        #expect(EventBarrierPolicy.Bound.main.wait(timeout: .milliseconds(300), count: 2) == .milliseconds(600))
    }

    @Test("A fallback keeps its designed bound")
    func fallbackWait() {
        #expect(EventBarrierPolicy.Bound.fallback.wait(timeout: .milliseconds(100), count: 2) == .milliseconds(200))
        #expect(EventBarrierPolicy.Bound.fallback.wait(timeout: .milliseconds(250), count: 2) == .milliseconds(500))
    }

    @Test("Without a barrier timeout every attempt runs")
    func allAttempts() {
        var budget = EventBarrierPolicy.AttemptBudget(maxAttempts: 4)
        let retries = (1...4).map { budget.allowsRetry(afterFailedAttempt: $0, barrierTimedOut: false) }
        #expect(retries == [true, true, true, false])
    }

    @Test("A barrier timeout allows one more attempt", arguments: [1, 3, 7])
    func oneMoreAttempt(timedOutAttempt: Int) {
        var budget = EventBarrierPolicy.AttemptBudget(maxAttempts: 8)
        let before = (1..<timedOutAttempt).map { budget.allowsRetry(afterFailedAttempt: $0, barrierTimedOut: false) }
        let afterTimeout = budget.allowsRetry(afterFailedAttempt: timedOutAttempt, barrierTimedOut: true)
        let afterNext = budget.allowsRetry(afterFailedAttempt: timedOutAttempt + 1, barrierTimedOut: false)
        #expect(before.allSatisfy { $0 })
        #expect(afterTimeout)
        #expect(!afterNext)
    }

    @Test("A timeout in the last attempt allows none")
    func lastAttempt() {
        var budget = EventBarrierPolicy.AttemptBudget(maxAttempts: 4)
        for attempt in 1...3 {
            _ = budget.allowsRetry(afterFailedAttempt: attempt, barrierTimedOut: false)
        }
        let retry = budget.allowsRetry(afterFailedAttempt: 4, barrierTimedOut: true)
        #expect(!retry)
    }

    @Test("A barrier timeout does not grow the move timeout")
    func moveTimeout() {
        #expect(EventBarrierPolicy.moveTimeout(afterFailure: .milliseconds(100), barrierTimedOut: true) == .milliseconds(100))
        #expect(EventBarrierPolicy.moveTimeout(afterFailure: .milliseconds(100), barrierTimedOut: false) == .milliseconds(150))
    }
}
