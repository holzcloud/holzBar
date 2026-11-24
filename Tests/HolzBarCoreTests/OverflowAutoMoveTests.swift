import Testing
@testable import HolzBarCore

@Suite("Overflow auto move")
struct OverflowAutoMoveTests {
    // The gate is changed outside `#expect`, whose expansion cannot call a mutating method.

    private let start = ContinuousClock.now

    /// A gate whose quiet start is over at `start + 60 s`.
    private func gate() -> OverflowAutoMove {
        OverflowAutoMove(startedAt: start)
    }

    /// Conditions under which a pass may run.
    private let good = OverflowAutoMove.Conditions(
        isSettled: true,
        isDragging: false,
        inLaunchGrace: false,
        isLayoutOpen: false,
        hasCandidates: true
    )

    private func conditions(
        settled: Bool = true,
        dragging: Bool = false,
        grace: Bool = false,
        layout: Bool = false,
        candidates: Bool = true
    ) -> OverflowAutoMove.Conditions {
        OverflowAutoMove.Conditions(
            isSettled: settled,
            isDragging: dragging,
            inLaunchGrace: grace,
            isLayoutOpen: layout,
            hasCandidates: candidates
        )
    }

    /// Two folded readings 5 s apart from `time` on; returns the second decision.
    private func confirm(_ gate: inout OverflowAutoMove, at time: ContinuousClock.Instant, with conditions: OverflowAutoMove.Conditions? = nil) -> OverflowAutoMove.Decision {
        let using = conditions ?? good
        _ = gate.note(.folded, conditions: using, at: time)
        return gate.note(.folded, conditions: using, at: time + OverflowAutoMove.Policy.readGap)
    }

    // MARK: Two reads

    @Test("An unknown reading never gives a pass")
    func unknownNeverPasses() {
        var gate = gate()
        for second in stride(from: 61, to: 200, by: 7) {
            let decision = gate.note(.unknown, conditions: good, at: start + .seconds(second))
            #expect(decision == .nothing)
        }
    }

    @Test("A clear reading gives nothing")
    func clearGivesNothing() {
        var gate = gate()
        #expect(gate.note(.clear, conditions: good, at: start + .seconds(100)) == .nothing)
    }

    @Test("One folded reading asks for a second one five seconds later")
    func oneReadIsNotEnough() {
        var gate = gate()
        let now = start + .seconds(100)
        #expect(gate.note(.folded, conditions: good, at: now) == .check(at: now + .seconds(5)))
    }

    @Test("A second folded reading five seconds later passes")
    func secondReadPasses() {
        var gate = gate()
        #expect(confirm(&gate, at: start + .seconds(100)) == .runPass)
    }

    @Test("A second folded reading too early waits for the gap")
    func secondReadTooEarlyWaits() {
        var gate = gate()
        let now = start + .seconds(100)
        _ = gate.note(.folded, conditions: good, at: now)
        #expect(gate.note(.folded, conditions: good, at: now + .seconds(2)) == .check(at: now + .seconds(5)))
        #expect(gate.note(.folded, conditions: good, at: now + .seconds(5)) == .runPass)
    }

    @Test("A clear or unknown reading between the two folded ones starts the confirmation again")
    func interruptionStartsAgain() {
        var gate = gate()
        let now = start + .seconds(100)
        _ = gate.note(.folded, conditions: good, at: now)
        _ = gate.note(.unknown, conditions: good, at: now + .seconds(3))
        // The first read no longer counts: this one is a first read again.
        #expect(gate.note(.folded, conditions: good, at: now + .seconds(6)) == .check(at: now + .seconds(11)))
        _ = gate.note(.clear, conditions: good, at: now + .seconds(8))
        #expect(gate.note(.folded, conditions: good, at: now + .seconds(12)) == .check(at: now + .seconds(17)))
    }

    // MARK: Quiet start

    @Test("Before 60 seconds after the start a folded reading waits for the end of the quiet start")
    func quietStart() {
        var gate = gate()
        let now = start + .seconds(10)
        #expect(gate.note(.folded, conditions: good, at: now) == .check(at: start + .seconds(60)))
        #expect(gate.note(.folded, conditions: good, at: start + .seconds(59)) == .check(at: start + .seconds(60)))
        #expect(confirm(&gate, at: start + .seconds(60)) == .runPass)
    }

    @Test("Settling after a wake restarts the quiet start")
    func settleRestartsQuietStart() {
        var gate = gate()
        _ = gate.note(.folded, conditions: good, at: start + .seconds(100))
        let settled = start + .seconds(500)
        gate.didSettle(at: settled)
        // The first read before the settle does not count any more.
        #expect(gate.note(.folded, conditions: good, at: settled + .seconds(10)) == .check(at: settled + .seconds(60)))
        #expect(confirm(&gate, at: settled + .seconds(60)) == .runPass)
    }

    // MARK: Conditions

    @Test("Every closed condition gives nothing for a confirmed fold")
    func closedConditionsGiveNothing() {
        let closed = [
            conditions(layout: true),
            conditions(dragging: true),
            conditions(grace: true),
            conditions(settled: false),
            conditions(candidates: false),
        ]
        for condition in closed {
            var gate = gate()
            #expect(confirm(&gate, at: start + .seconds(100), with: condition) == .nothing)
        }
    }

    @Test("A closed condition throws the first read away")
    func closedConditionResetsConfirmation() {
        var gate = gate()
        let now = start + .seconds(100)
        _ = gate.note(.folded, conditions: good, at: now)
        _ = gate.note(.folded, conditions: conditions(dragging: true), at: now + .seconds(2))
        #expect(gate.note(.folded, conditions: good, at: now + .seconds(6)) == .check(at: now + .seconds(11)))
    }

    // MARK: Episode

    @Test("A pass never triggers a pass")
    func aPassNeverTriggersAPass() {
        var gate = gate()
        var now = start + .seconds(100)
        #expect(confirm(&gate, at: now) == .runPass)
        now += .seconds(5)
        gate.didRunPass(at: now)
        // The bar stays folded after the move (the fold did not end): reading after reading,
        // for as long as it lasts, never gives a second pass.
        var decisions = [OverflowAutoMove.Decision]()
        for second in stride(from: 3, through: 600, by: 3) {
            decisions.append(gate.note(.folded, conditions: good, at: now + .seconds(second)))
        }
        #expect(decisions.allSatisfy { $0 == .nothing })
    }

    @Test("Within two seconds after a pass every reading waits for the end of that time")
    func quietAfterPass() {
        var gate = gate()
        let passAt = start + .seconds(100)
        gate.didRunPass(at: passAt)
        let end = passAt + OverflowAutoMove.Policy.afterPass
        #expect(gate.note(.folded, conditions: good, at: passAt + .seconds(1)) == .check(at: end))
        #expect(gate.note(.clear, conditions: good, at: passAt + .milliseconds(500)) == .check(at: end))
        #expect(gate.note(.unknown, conditions: good, at: passAt + .milliseconds(1999)) == .check(at: end))
        #expect(gate.note(.folded, conditions: good, at: end) == .nothing)
    }

    @Test("Thirty seconds without overflow end the episode")
    func clearEndsEpisode() {
        var gate = gate()
        let passAt = start + .seconds(100)
        gate.didRunPass(at: passAt)
        _ = gate.note(.clear, conditions: good, at: passAt + .seconds(10))
        let later = passAt + .seconds(45)
        #expect(gate.note(.folded, conditions: good, at: later) == .check(at: later + .seconds(5)))
        #expect(gate.note(.folded, conditions: good, at: later + .seconds(5)) == .runPass)
    }

    @Test("A fold within thirty seconds of clear keeps the episode")
    func foldWithinThirtySecondsKeepsEpisode() {
        var gate = gate()
        let passAt = start + .seconds(100)
        gate.didRunPass(at: passAt)
        _ = gate.note(.clear, conditions: good, at: passAt + .seconds(10))
        #expect(gate.note(.folded, conditions: good, at: passAt + .seconds(25)) == .nothing)
        // The clear streak began again with that fold: a later fold is still the same episode.
        #expect(gate.note(.folded, conditions: good, at: passAt + .seconds(90)) == .nothing)
        #expect(gate.note(.folded, conditions: good, at: passAt + .seconds(100)) == .nothing)
    }

    @Test("An unknown reading does not end the episode and interrupts the clear streak")
    func unknownDoesNotEndEpisode() {
        var gate = gate()
        let passAt = start + .seconds(100)
        gate.didRunPass(at: passAt)
        _ = gate.note(.clear, conditions: good, at: passAt + .seconds(5))
        _ = gate.note(.unknown, conditions: good, at: passAt + .seconds(20))
        // 40 s after the first clear reading, but the streak was interrupted.
        #expect(gate.note(.folded, conditions: good, at: passAt + .seconds(45)) == .nothing)
    }

    // MARK: Breaker

    @Test("Three passes in ten minutes pause the gate until the oldest one leaves the window")
    func breaker() {
        var gate = gate()
        // Three passes, each in its own episode (30 s of clear between).
        let passTimes = [100, 200, 300].map { start + .seconds($0) }
        for time in passTimes {
            gate.didRunPass(at: time)
            _ = gate.note(.clear, conditions: good, at: time + .seconds(3))
        }
        #expect(gate.isPaused(at: start + .seconds(400)))
        let until = passTimes[0] + OverflowAutoMove.Policy.breakerWindow
        // A confirmed fold waits for the end of the pause.
        let first = gate.note(.folded, conditions: good, at: start + .seconds(400))
        let second = gate.note(.folded, conditions: good, at: start + .seconds(406))
        #expect(first == .check(at: until))
        #expect(second == .check(at: until))
        #expect(gate.isPaused(at: until - .seconds(1)))
        #expect(!gate.isPaused(at: until))
        // After the pause the confirmation starts from nothing.
        #expect(gate.note(.folded, conditions: good, at: until) == .check(at: until + .seconds(5)))
        #expect(gate.note(.folded, conditions: good, at: until + .seconds(5)) == .runPass)
    }

    @Test("Two passes in ten minutes do not pause the gate")
    func twoPassesDoNotPause() {
        var gate = gate()
        gate.didRunPass(at: start + .seconds(100))
        gate.didRunPass(at: start + .seconds(200))
        #expect(!gate.isPaused(at: start + .seconds(300)))
    }

    @Test("Passes outside the window are not counted")
    func oldPassesAreNotCounted() {
        var gate = gate()
        gate.didRunPass(at: start + .seconds(100))
        gate.didRunPass(at: start + .seconds(200))
        gate.didRunPass(at: start + .seconds(701))
        #expect(!gate.isPaused(at: start + .seconds(702)))
    }

    // MARK: Policy

    @Test("The policy numbers are the assumed values")
    func policyNumbers() {
        #expect(OverflowAutoMove.Policy.readGap == .seconds(5))
        #expect(OverflowAutoMove.Policy.episodeEnd == .seconds(30))
        #expect(OverflowAutoMove.Policy.quietStart == .seconds(60))
        #expect(OverflowAutoMove.Policy.breakerWindow == .seconds(600))
        #expect(OverflowAutoMove.Policy.breakerLimit == 3)
        #expect(OverflowAutoMove.Policy.afterPass == .seconds(2))
    }
}
