import Testing
@testable import HolzBarCore

@Suite("ThresholdEvaluator")
struct ThresholdEvaluatorTests {
    private typealias Instant = SuspendingClock.Instant
    private typealias Effect = ThresholdEvaluator.Effect

    private let origin = SuspendingClock.now

    private func at(_ seconds: Int) -> Instant {
        origin.advanced(by: .seconds(seconds))
    }

    private func cpuRule(limit: Int = 90, hold: AlertHold = .fiveMinutes) -> ThresholdRule {
        ThresholdRule(signal: .cpu, isOn: true, limit: limit, hold: hold)
    }

    /// An evaluator with one CPU rule, configured at second 0 and past its quiet period.
    private func cpuEvaluator(limit: Int = 90, hold: AlertHold = .fiveMinutes) -> ThresholdEvaluator {
        var evaluator = ThresholdEvaluator()
        _ = evaluator.configure([cpuRule(limit: limit, hold: hold)], at: at(0))
        return evaluator
    }

    // MARK: Zones

    @Test("CPU load enters above the threshold and leaves below the threshold minus five")
    func cpuZones() {
        let rule = cpuRule()
        func zone(_ fraction: Double) -> AlertZone? {
            AlertZone.zone(of: .fraction(fraction), rule: rule)
        }
        #expect(zone(0.91) == .firing)
        #expect(zone(0.90) == .between)
        #expect(zone(0.85) == .between)
        #expect(zone(0.84) == .recovered)
        #expect(zone(1.0) == .firing)
        #expect(zone(0.0) == .recovered)
    }

    @Test("CPU load is one whole percent, rounded half away from zero and clamped")
    func cpuPercent() {
        #expect(AlertZone.cpuPercent(0.845) == 85)
        #expect(AlertZone.cpuPercent(0.904) == 90)
        #expect(AlertZone.cpuPercent(1.7) == 100)
        #expect(AlertZone.cpuPercent(-0.2) == 0)
        #expect(AlertZone.cpuPercent(.nan) == nil)
        #expect(AlertZone.cpuPercent(.infinity) == nil)
        #expect(AlertZone.cpuPercent(-.infinity) == nil)
    }

    @Test("An unavailable observation or one of the wrong kind has no zone")
    func noZone() {
        let rule = cpuRule()
        #expect(AlertZone.zone(of: .unavailable, rule: rule) == nil)
        #expect(AlertZone.zone(of: .freeBytes(1), rule: rule) == nil)
        #expect(AlertZone.zone(of: .fraction(.nan), rule: rule) == nil)
    }

    // MARK: The CPU path

    @Test("A hold of five minutes fires at the first evaluation at or after its end, never earlier")
    func holdFiresAtItsEnd() {
        var evaluator = cpuEvaluator()
        #expect(evaluator.observe(.fraction(0.91), for: .cpu, at: at(100)).isEmpty)
        #expect(evaluator.nextDeadline() == at(400))
        #expect(evaluator.advance(to: at(399)).isEmpty)
        #expect(evaluator.firing.isEmpty)
        let effects = evaluator.advance(to: at(400))
        #expect(effects == [.fired(AlertSnapshot(signal: .cpu, severity: .amber, observation: .fraction(0.91)))])
        #expect(evaluator.firing[.cpu]?.severity == .amber)
    }

    @Test("A load at the threshold itself never starts a hold")
    func atTheThresholdNothingStarts() {
        var evaluator = cpuEvaluator()
        #expect(evaluator.observe(.fraction(0.90), for: .cpu, at: at(100)).isEmpty)
        #expect(evaluator.nextDeadline() == nil)
        #expect(evaluator.advance(to: at(1_000)).isEmpty)
    }

    @Test("A firing alert survives a value inside the band")
    func bandKeepsTheAlert() {
        var evaluator = cpuEvaluator(hold: .immediately)
        let fired = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        #expect(fired.count == 1)
        // 85 % is inside the band: no clear, and the shorter value is an update, not an end.
        let effects = evaluator.observe(.fraction(0.845), for: .cpu, at: at(110))
        #expect(!effects.contains(.cleared(.cpu)))
        #expect(evaluator.advance(to: at(1_000)).isEmpty)
        #expect(evaluator.firing[.cpu] != nil)
    }

    @Test("Thirty seconds below the exit clear the alert, not twenty-nine")
    func clearHold() {
        var evaluator = cpuEvaluator(hold: .immediately)
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        #expect(!evaluator.observe(.fraction(0.80), for: .cpu, at: at(200)).contains(.cleared(.cpu)))
        #expect(evaluator.nextDeadline() == at(230))
        #expect(!evaluator.observe(.fraction(0.80), for: .cpu, at: at(229)).contains(.cleared(.cpu)))
        #expect(evaluator.observe(.fraction(0.80), for: .cpu, at: at(230)).contains(.cleared(.cpu)))
        #expect(evaluator.firing.isEmpty)
        #expect(evaluator.nextDeadline() == nil)
    }

    @Test("The clear can also come by the deadline, with no new reading")
    func clearByDeadline() {
        var evaluator = cpuEvaluator(hold: .immediately)
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = evaluator.observe(.fraction(0.80), for: .cpu, at: at(200))
        #expect(evaluator.advance(to: at(229)).isEmpty)
        #expect(evaluator.advance(to: at(230)) == [.cleared(.cpu)])
    }

    @Test("An unavailable or non-finite load changes nothing")
    func unavailableChangesNothing() {
        var evaluator = cpuEvaluator()
        _ = evaluator.observe(.fraction(0.91), for: .cpu, at: at(100))
        let deadline = evaluator.nextDeadline()
        #expect(evaluator.observe(.unavailable, for: .cpu, at: at(500)).isEmpty)
        #expect(evaluator.observe(.fraction(.nan), for: .cpu, at: at(500)).isEmpty)
        #expect(evaluator.nextDeadline() == deadline)
        #expect(evaluator.firing.isEmpty)
    }

    @Test("An observation for a rule that is off or missing is ignored")
    func offRuleIgnored() {
        var evaluator = ThresholdEvaluator()
        #expect(evaluator.observe(.fraction(0.99), for: .cpu, at: at(100)).isEmpty)
        var off = cpuRule()
        off.isOn = false
        _ = evaluator.configure([off], at: at(0))
        #expect(evaluator.observe(.fraction(0.99), for: .cpu, at: at(100)).isEmpty)
        #expect(evaluator.nextDeadline() == nil)
    }

    @Test("Without any pending or firing alert there is no deadline")
    func noDeadline() {
        let evaluator = cpuEvaluator()
        #expect(evaluator.nextDeadline() == nil)
    }
}
