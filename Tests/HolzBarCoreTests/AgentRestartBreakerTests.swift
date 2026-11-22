import Testing
@testable import HolzBarCore

@Suite("MenuBarAgent restart breaker")
struct AgentRestartBreakerTests {
    // The breaker is changed outside `#expect`, whose expansion cannot call a mutating method.

    private let start = ContinuousClock.now

    @Test("The fourth restart within ten minutes trips it for 30 minutes")
    func fourthRestartTrips() {
        var breaker = AgentRestartBreaker()
        let first = breaker.record(at: start)
        let second = breaker.record(at: start + .seconds(60))
        let third = breaker.record(at: start + .seconds(120))
        #expect([first, second, third] == [.reapply, .reapply, .reapply])
        #expect(!breaker.isTripped(at: start + .seconds(120)))
        let fourth = breaker.record(at: start + .seconds(180))
        #expect(fourth == .tripped)
        #expect(breaker.isTripped(at: start + .seconds(180)))
        #expect(breaker.isTripped(at: start + .seconds(180 + 29 * 60)))
        #expect(!breaker.isTripped(at: start + .seconds(180 + 30 * 60)))
    }

    @Test("Restarts spread over more than the window never trip it")
    func slidingWindow() {
        var breaker = AgentRestartBreaker()
        var outcomes = [AgentRestartBreaker.Outcome]()
        for index in 0..<20 {
            outcomes.append(breaker.record(at: start + .seconds(index * 660)))
        }
        #expect(outcomes.allSatisfy { $0 == .reapply })
        #expect(!breaker.isTripped(at: start + .seconds(20 * 660)))
    }

    @Test("A restart holzBar expects is not counted, once")
    func expectedRestart() {
        var breaker = AgentRestartBreaker()
        let accepted1 = breaker.expectRestart(at: start)
        #expect(accepted1)
        let expected = breaker.record(at: start + .seconds(3))
        #expect(expected == .expected)
        // One expectation covers one restart.
        let counted = breaker.record(at: start + .seconds(4))
        #expect(counted == .reapply)
    }

    @Test("An expected restart that comes too late is counted")
    func lateExpectedRestart() {
        var breaker = AgentRestartBreaker()
        let accepted2 = breaker.expectRestart(at: start)
        #expect(accepted2)
        let late = breaker.record(at: start + .seconds(11))
        #expect(late == .reapply)
    }

    @Test("Expected restarts never trip it")
    func expectedRestartsDoNotTrip() {
        var breaker = AgentRestartBreaker()
        var outcomes = [AgentRestartBreaker.Outcome]()
        for index in 0..<10 {
            let at = start + .seconds(index * 20)
            breaker.expectRestart(at: at)
            outcomes.append(breaker.record(at: at + .seconds(2)))
        }
        #expect(outcomes.allSatisfy { $0 == .expected })
        #expect(!breaker.isTripped(at: start + .seconds(200)))
    }

    @Test("Two expectations less than the manual gap apart count as one")
    func manualGap() {
        var breaker = AgentRestartBreaker()
        let accepted3 = breaker.expectRestart(at: start)
        #expect(accepted3)
        let accepted4 = breaker.expectRestart(at: start + .seconds(4))
        #expect(!accepted4)
        let accepted5 = breaker.expectRestart(at: start + .seconds(5))
        #expect(accepted5)
    }

    @Test("Reset ends a trip and the next three restarts reapply")
    func resetEndsATrip() {
        var breaker = AgentRestartBreaker()
        for index in 0..<4 {
            breaker.record(at: start + .seconds(index))
        }
        #expect(breaker.isTripped(at: start + .seconds(10)))
        breaker.reset()
        #expect(!breaker.isTripped(at: start + .seconds(10)))
        var outcomes = [AgentRestartBreaker.Outcome]()
        for index in 0..<3 {
            outcomes.append(breaker.record(at: start + .seconds(20 + index)))
        }
        #expect(outcomes == [.reapply, .reapply, .reapply])
    }

    @Test("A restart while tripped stays tripped and does not shorten or extend the trip")
    func restartWhileTripped() {
        var breaker = AgentRestartBreaker()
        for index in 0..<4 {
            breaker.record(at: start + .seconds(index))
        }
        let until = breaker.trippedUntil
        let again = breaker.record(at: start + .seconds(600))
        #expect(again == .tripped)
        #expect(breaker.trippedUntil == until)
    }

    @Test("A reset keeps a pending expectation")
    func resetKeepsExpectation() {
        var breaker = AgentRestartBreaker()
        let accepted6 = breaker.expectRestart(at: start)
        #expect(accepted6)
        breaker.reset()
        let expected = breaker.record(at: start + .seconds(2))
        #expect(expected == .expected)
        // The manual gap stays too.
        let accepted7 = breaker.expectRestart(at: start + .seconds(3))
        #expect(!accepted7)
    }

    @Test("A trip after a reset ends at its own deadline, not at the earlier one")
    func tripAfterResetHasItsOwnDeadline() {
        var breaker = AgentRestartBreaker()
        for index in 0..<4 {
            breaker.record(at: start + .seconds(index))
        }
        let first = breaker.trippedUntil
        breaker.reset()
        #expect(breaker.trippedUntil == nil)
        for index in 0..<4 {
            breaker.record(at: start + .seconds(300 + index))
        }
        let second = breaker.trippedUntil
        #expect(second != nil)
        #expect(second != first)
        #expect(!breaker.isTripped(at: start + .seconds(300 + 3) + AgentRestartBreaker.trippedFor))
        // The first deadline has passed by the time the second trip stands; only the second
        // end is armed for it.
        #expect(breaker.isTripped(at: (first ?? start) + .seconds(1)))
    }

    @Test("Cancelling an expectation restores the manual gap and the pending expectation")
    func cancelExpectation() {
        var breaker = AgentRestartBreaker()
        let accepted = breaker.expectRestart(at: start)
        #expect(accepted)
        breaker.cancelExpectation()
        // The retry is not a double click.
        let retry = breaker.expectRestart(at: start + .seconds(1))
        #expect(retry)
        breaker.cancelExpectation()
        // The next restart is counted: nothing was expected.
        let outcome = breaker.record(at: start + .seconds(2))
        #expect(outcome == .reapply)
    }

    @Test("Cancelling keeps an earlier pending expectation")
    func cancelKeepsEarlierExpectation() {
        var breaker = AgentRestartBreaker()
        let first = breaker.expectRestart(at: start)
        #expect(first)
        let second = breaker.expectRestart(at: start + .seconds(6))
        #expect(second)
        breaker.cancelExpectation()
        let outcome = breaker.record(at: start + .seconds(8))
        #expect(outcome == .expected)
    }

    @Test("Cancelling without an expectation does nothing")
    func cancelWithoutExpectation() {
        var breaker = AgentRestartBreaker()
        breaker.cancelExpectation()
        #expect(breaker == AgentRestartBreaker())
    }
}
