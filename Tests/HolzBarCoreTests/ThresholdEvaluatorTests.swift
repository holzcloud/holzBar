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

    // MARK: Helpers for several signals

    private func rule(
        _ signal: AlertSignal,
        limit: Int? = nil,
        hold: AlertHold = .immediately
    ) -> ThresholdRule {
        var rule = ThresholdRule.defaultRule(for: signal)
        rule.isOn = true
        rule.hold = hold
        if let limit {
            rule.limit = limit
        }
        return rule
    }

    private func configured(_ rules: [ThresholdRule], at seconds: Int = 0) -> ThresholdEvaluator {
        var evaluator = ThresholdEvaluator()
        _ = evaluator.configure(rules, at: at(seconds))
        return evaluator
    }

    private func firedSignals(_ effects: [Effect]) -> [AlertSignal] {
        effects.compactMap { effect in
            if case .fired(let snapshot) = effect {
                snapshot.signal
            } else {
                nil
            }
        }
    }

    private func count(_ effects: [Effect], where matches: (Effect) -> Bool) -> Int {
        effects.filter(matches).count
    }

    // MARK: Zones of every signal

    @Test("Memory pressure at Warning fires on Warning and Critical, at Critical on Critical only")
    func memoryZones() {
        let warning = rule(.memoryPressure, limit: 1)
        #expect(AlertZone.zone(of: .pressure(.warning), rule: warning) == .firing)
        #expect(AlertZone.zone(of: .pressure(.critical), rule: warning) == .firing)
        #expect(AlertZone.zone(of: .pressure(.normal), rule: warning) == .recovered)
        let critical = rule(.memoryPressure, limit: 2)
        #expect(AlertZone.zone(of: .pressure(.warning), rule: critical) == .recovered)
        #expect(AlertZone.zone(of: .pressure(.critical), rule: critical) == .firing)
    }

    @Test("Thermal state at Serious fires on Serious and Critical")
    func thermalZones() {
        let serious = rule(.thermal, limit: 2)
        #expect(AlertZone.zone(of: .thermal(.critical), rule: serious) == .firing)
        #expect(AlertZone.zone(of: .thermal(.serious), rule: serious) == .firing)
        #expect(AlertZone.zone(of: .thermal(.fair), rule: serious) == .recovered)
        #expect(AlertZone.zone(of: .thermal(.nominal), rule: serious) == .recovered)
        let fair = rule(.thermal, limit: 1)
        #expect(AlertZone.zone(of: .thermal(.fair), rule: fair) == .firing)
        #expect(AlertZone.zone(of: .thermal(.nominal), rule: fair) == .recovered)
    }

    @Test("Free disk space enters below the threshold in decimal gigabytes and leaves a margin above it")
    func diskZones() {
        let ten = rule(.freeDisk, limit: 10)
        #expect(AlertZone.zone(of: .freeBytes(9_999_999_999), rule: ten) == .firing)
        #expect(AlertZone.zone(of: .freeBytes(10_000_000_000), rule: ten) == .between)
        #expect(AlertZone.zone(of: .freeBytes(10_999_999_999), rule: ten) == .between)
        #expect(AlertZone.zone(of: .freeBytes(11_000_000_000), rule: ten) == .recovered)
        let twoHundred = rule(.freeDisk, limit: 200)
        #expect(AlertZone.zone(of: .freeBytes(219_999_999_999), rule: twoHundred) == .between)
        #expect(AlertZone.zone(of: .freeBytes(220_000_000_000), rule: twoHundred) == .recovered)
        let five = rule(.freeDisk, limit: 5)
        #expect(AlertZone.zone(of: .freeBytes(5_999_999_999), rule: five) == .between)
        #expect(AlertZone.zone(of: .freeBytes(6_000_000_000), rule: five) == .recovered)
        #expect(AlertZone.zone(of: .freeBytes(-1), rule: five) == nil)
    }

    @Test("The Mac battery enters below the threshold on battery power and leaves five points above")
    func batteryZones() {
        let twenty = rule(.macBattery, limit: 20)
        #expect(AlertZone.zone(of: .battery(percent: 19, onBattery: true), rule: twenty) == .firing)
        #expect(AlertZone.zone(of: .battery(percent: 20, onBattery: true), rule: twenty) == .between)
        #expect(AlertZone.zone(of: .battery(percent: 24, onBattery: true), rule: twenty) == .between)
        #expect(AlertZone.zone(of: .battery(percent: 25, onBattery: true), rule: twenty) == .recovered)
        #expect(AlertZone.zone(of: .battery(percent: 10, onBattery: false), rule: twenty) == .unplugged)
        #expect(AlertZone.zone(of: .battery(percent: 101, onBattery: true), rule: twenty) == nil)
    }

    // MARK: The Mac battery

    @Test("Plugging in clears a firing battery alert in the same call, with no clear hold")
    func pluggingInClears() {
        var evaluator = configured([rule(.macBattery, limit: 20)])
        #expect(firedSignals(evaluator.observe(.battery(percent: 15, onBattery: true), for: .macBattery, at: at(100))) == [.macBattery])
        let effects = evaluator.observe(.battery(percent: 15, onBattery: false), for: .macBattery, at: at(110))
        #expect(effects == [.cleared(.macBattery)])
        #expect(evaluator.firing.isEmpty)
        #expect(evaluator.nextDeadline() == nil)
    }

    @Test("A low battery on a Mac that is plugged in starts nothing")
    func pluggedInStartsNothing() {
        var evaluator = configured([rule(.macBattery, limit: 20, hold: .oneMinute)])
        #expect(evaluator.observe(.battery(percent: 5, onBattery: false), for: .macBattery, at: at(100)).isEmpty)
        #expect(evaluator.nextDeadline() == nil)
    }

    // MARK: Quiet period

    @Test("After a resume a fire is deferred to the end of the quiet period, not dropped")
    func quietDefersTheFire() {
        var evaluator = configured([rule(.thermal)])
        evaluator.resume(at: at(1_000))
        #expect(evaluator.observe(.thermal(.serious), for: .thermal, at: at(1_001)).isEmpty)
        #expect(evaluator.nextDeadline() == at(1_030))
        #expect(evaluator.advance(to: at(1_029)).isEmpty)
        #expect(firedSignals(evaluator.advance(to: at(1_030))) == [.thermal])
    }

    @Test("A value that recovered during the quiet period fires nothing and the signal is idle after the clear hold")
    func quietThenRecovered() {
        var evaluator = configured([rule(.thermal)])
        evaluator.resume(at: at(1_000))
        _ = evaluator.observe(.thermal(.serious), for: .thermal, at: at(1_001))
        _ = evaluator.observe(.thermal(.nominal), for: .thermal, at: at(1_010))
        #expect(evaluator.advance(to: at(1_030)).isEmpty)
        #expect(evaluator.advance(to: at(1_040)).isEmpty)
        #expect(evaluator.nextDeadline() == nil)
        #expect(evaluator.firing.isEmpty)
    }

    @Test("A rule that was just switched on is quiet for thirty seconds")
    func enablingIsQuiet() {
        var evaluator = ThresholdEvaluator()
        var off = rule(.thermal)
        off.isOn = false
        _ = evaluator.configure([off], at: at(0))
        _ = evaluator.configure([rule(.thermal)], at: at(1_000))
        #expect(evaluator.observe(.thermal(.critical), for: .thermal, at: at(1_001)).isEmpty)
        #expect(evaluator.advance(to: at(1_029)).isEmpty)
        #expect(firedSignals(evaluator.advance(to: at(1_030))) == [.thermal])
    }

    @Test("The first configuration is quiet for thirty seconds too")
    func startingIsQuiet() {
        var evaluator = configured([rule(.thermal)], at: 500)
        #expect(evaluator.observe(.thermal(.critical), for: .thermal, at: at(510)).isEmpty)
        #expect(firedSignals(evaluator.advance(to: at(530))) == [.thermal])
    }

    // MARK: Configure

    @Test("Switching a firing rule off ends its alert with no done hold")
    func switchingOffEnds() {
        var evaluator = configured([rule(.cpu), rule(.thermal)])
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = evaluator.observe(.thermal(.serious), for: .thermal, at: at(100))
        var off = rule(.cpu)
        off.isOn = false
        #expect(evaluator.configure([off, rule(.thermal)], at: at(200)) == [.ended(.cpu)])
        #expect(evaluator.firing.keys.contains(.thermal))
        #expect(!evaluator.firing.keys.contains(.cpu))
    }

    @Test("Raising the threshold past the last value ends the alert, a value in the new band keeps it")
    func raisingTheThreshold() {
        var past = configured([rule(.cpu, limit: 90)])
        _ = past.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = past.observe(.fraction(0.89), for: .cpu, at: at(110))
        #expect(past.configure([rule(.cpu, limit: 95)], at: at(120)) == [.ended(.cpu)])
        #expect(past.firing.isEmpty)

        var inside = configured([rule(.cpu, limit: 90)])
        _ = inside.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = inside.observe(.fraction(0.91), for: .cpu, at: at(110))
        #expect(inside.configure([rule(.cpu, limit: 95)], at: at(120)).isEmpty)
        #expect(inside.firing[.cpu] != nil)
    }

    @Test("Lowering the threshold keeps the alert and updates it only if its severity changed")
    func loweringTheThreshold() {
        var changed = configured([rule(.cpu, limit: 90)])
        _ = changed.observe(.fraction(0.94), for: .cpu, at: at(100))
        let effects = changed.configure([rule(.cpu, limit: 85)], at: at(110))
        #expect(effects == [.updated(AlertSnapshot(signal: .cpu, severity: .red, observation: .fraction(0.94)))])

        var same = configured([rule(.cpu, limit: 90)])
        _ = same.observe(.fraction(0.91), for: .cpu, at: at(100))
        #expect(same.configure([rule(.cpu, limit: 85)], at: at(110)).isEmpty)
        #expect(same.firing[.cpu]?.severity == .amber)
    }

    @Test("Changing the hold of a pending rule keeps its start")
    func holdChangeKeepsTheStart() {
        var longer = configured([rule(.cpu, hold: .fiveMinutes)])
        _ = longer.observe(.fraction(0.95), for: .cpu, at: at(100))
        #expect(longer.configure([rule(.cpu, hold: .fifteenMinutes)], at: at(150)).isEmpty)
        #expect(longer.nextDeadline() == at(1_000))

        var shorter = configured([rule(.cpu, hold: .fiveMinutes)])
        _ = shorter.observe(.fraction(0.95), for: .cpu, at: at(100))
        #expect(shorter.nextDeadline() == at(400))
        let effects = shorter.configure([rule(.cpu, hold: .tenSeconds)], at: at(150))
        #expect(firedSignals(effects) == [.cpu])
    }

    @Test("A stray limit in a rule is validated by the evaluator")
    func configureValidates() {
        var evaluator = configured([ThresholdRule(signal: .cpu, isOn: true, limit: 12, hold: .immediately)])
        // 12 becomes 50, so a load of 51 % is above it.
        #expect(firedSignals(evaluator.observe(.fraction(0.51), for: .cpu, at: at(100))) == [.cpu])
    }

    // MARK: Cooldown and rate cap

    @Test("A cleared alert that comes back fires again only thirty minutes after its last fire")
    func cooldownDefersTheFire() {
        var evaluator = configured([rule(.cpu, hold: .fiveMinutes)])
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        #expect(firedSignals(evaluator.advance(to: at(400))) == [.cpu])
        _ = evaluator.observe(.fraction(0.5), for: .cpu, at: at(410))
        #expect(evaluator.advance(to: at(440)) == [.cleared(.cpu)])
        // It comes back three minutes after the first fire, with a hold of five minutes.
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(580))
        #expect(evaluator.nextDeadline() == at(2_200))
        #expect(evaluator.advance(to: at(880)).isEmpty)
        #expect(evaluator.advance(to: at(2_199)).isEmpty)
        #expect(firedSignals(evaluator.advance(to: at(2_200))) == [.cpu])
    }

    @Test("A deferred fire does not happen when the value has recovered by then")
    func cooldownThenRecovered() {
        var evaluator = configured([rule(.cpu, hold: .immediately)])
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = evaluator.observe(.fraction(0.5), for: .cpu, at: at(200))
        _ = evaluator.advance(to: at(230))
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(300))
        _ = evaluator.observe(.fraction(0.5), for: .cpu, at: at(1_000))
        #expect(evaluator.advance(to: at(2_000)).isEmpty)
        #expect(evaluator.advance(to: at(2_200)).isEmpty)
        #expect(evaluator.firing.isEmpty)
        #expect(evaluator.nextDeadline() == nil)
    }

    @Test("A fifth fire within an hour waits until the oldest of the last four is an hour old")
    func rateCapDefersTheFifthFire() {
        var evaluator = configured([
            rule(.cpu), rule(.memoryPressure, limit: 1), rule(.thermal), rule(.freeDisk, limit: 10), rule(.macBattery, limit: 20)
        ])
        #expect(firedSignals(evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))) == [.cpu])
        #expect(firedSignals(evaluator.observe(.pressure(.critical), for: .memoryPressure, at: at(200))) == [.memoryPressure])
        #expect(firedSignals(evaluator.observe(.thermal(.serious), for: .thermal, at: at(300))) == [.thermal])
        #expect(firedSignals(evaluator.observe(.freeBytes(1_000_000_000), for: .freeDisk, at: at(400))) == [.freeDisk])
        #expect(evaluator.observe(.battery(percent: 10, onBattery: true), for: .macBattery, at: at(500)).isEmpty)
        #expect(evaluator.firing[.macBattery] == nil)
        // The deferred fire is on the schedule: an hour after the first of the four.
        #expect(evaluator.nextDeadline() == at(3_700))
        #expect(evaluator.advance(to: at(3_699)).isEmpty)
        #expect(firedSignals(evaluator.advance(to: at(3_700))) == [.macBattery])
    }

    // MARK: Rest and resume

    @Test("A rest ends every firing alert, drops a running hold and keeps the cooldown")
    func restEndsEverything() {
        var evaluator = configured([rule(.cpu), rule(.thermal), rule(.freeDisk, limit: 10, hold: .oneMinute)])
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = evaluator.observe(.thermal(.serious), for: .thermal, at: at(110))
        _ = evaluator.observe(.freeBytes(1_000_000_000), for: .freeDisk, at: at(120))
        #expect(evaluator.rest(at: at(130)) == [.ended(.cpu), .ended(.thermal)])
        #expect(evaluator.firing.isEmpty)
        #expect(evaluator.nextDeadline() == nil)
    }

    @Test("After a resume nothing fires for thirty seconds")
    func resumeIsQuiet() {
        var evaluator = configured([rule(.thermal)])
        _ = evaluator.rest(at: at(200))
        evaluator.resume(at: at(300))
        #expect(evaluator.observe(.thermal(.critical), for: .thermal, at: at(305)).isEmpty)
        #expect(evaluator.advance(to: at(329)).isEmpty)
        #expect(firedSignals(evaluator.advance(to: at(330))) == [.thermal])
    }

    @Test("The history of fires survives a rest: a fire ten minutes before still blocks until thirty minutes after it")
    func historySurvivesRest() {
        var evaluator = configured([rule(.cpu)])
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = evaluator.rest(at: at(700))
        evaluator.resume(at: at(701))
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(800))
        #expect(evaluator.nextDeadline() == at(1_900))
        #expect(evaluator.advance(to: at(1_899)).isEmpty)
        #expect(firedSignals(evaluator.advance(to: at(1_900))) == [.cpu])
    }

    // MARK: ALRT-04 scenarios

    @Test("A twenty-minute hover at 89 and 91 percent around a 90 percent rule gives one fire and no clear")
    func hoverGivesOneAlert() {
        var evaluator = configured([rule(.cpu, limit: 90, hold: .fiveMinutes)])
        var effects: [Effect] = []
        for step in 0..<120 {
            let value = step.isMultiple(of: 2) ? 0.91 : 0.89
            effects += evaluator.observe(.fraction(value), for: .cpu, at: at(40 + step * 10))
        }
        #expect(count(effects) { if case .fired = $0 { true } else { false } } == 1)
        #expect(!effects.contains(.cleared(.cpu)))
        #expect(evaluator.firing[.cpu] != nil)
    }

    @Test("A dip below the exit shorter than thirty seconds neither resets a hold nor clears an alert")
    func shortDipChangesNothing() {
        var evaluator = configured([rule(.cpu, limit: 90, hold: .fiveMinutes)])
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        _ = evaluator.observe(.fraction(0.5), for: .cpu, at: at(200))
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(220))
        #expect(firedSignals(evaluator.advance(to: at(400))) == [.cpu])
        _ = evaluator.observe(.fraction(0.5), for: .cpu, at: at(500))
        #expect(!evaluator.observe(.fraction(0.95), for: .cpu, at: at(520)).contains(.cleared(.cpu)))
        #expect(evaluator.firing[.cpu] != nil)
    }

    @Test("A sleep and a wake never create a fire of their own")
    func sleepAndWakeCreateNoFire() {
        var evaluator = configured([rule(.cpu, limit: 90, hold: .immediately)])
        var effects = evaluator.observe(.fraction(1.0), for: .cpu, at: at(100))
        // The Mac rests; the suspending clock does not count the sleep, so the instants do not move.
        effects += evaluator.rest(at: at(160))
        evaluator.resume(at: at(161))
        effects += evaluator.observe(.fraction(1.0), for: .cpu, at: at(200))
        effects += evaluator.advance(to: at(1_000))
        #expect(count(effects) { if case .fired = $0 { true } else { false } } == 1)
        #expect(evaluator.firing.isEmpty)
        #expect(evaluator.nextDeadline() == at(1_900))
    }

    // MARK: Order, updates and deadlines

    @Test("Two rules that fire at the same instant are two effects in the order of the signals")
    func firingOrder() {
        var evaluator = configured([rule(.thermal), rule(.macBattery, limit: 20)])
        evaluator.resume(at: at(1_000))
        _ = evaluator.observe(.battery(percent: 19, onBattery: true), for: .macBattery, at: at(1_001))
        _ = evaluator.observe(.thermal(.serious), for: .thermal, at: at(1_002))
        let effects = evaluator.advance(to: at(1_030))
        #expect(effects == [
            .fired(AlertSnapshot(signal: .thermal, severity: .amber, observation: .thermal(.serious))),
            .fired(AlertSnapshot(signal: .macBattery, severity: .amber, observation: .battery(percent: 19, onBattery: true)))
        ])
    }

    @Test("A firing alert is updated when its whole percent or its severity changes, not otherwise")
    func updatedOnVisibleChange() {
        var evaluator = configured([rule(.cpu)])
        _ = evaluator.observe(.fraction(0.92), for: .cpu, at: at(100))
        #expect(evaluator.observe(.fraction(0.921), for: .cpu, at: at(110)).isEmpty)
        let moved = evaluator.observe(.fraction(0.93), for: .cpu, at: at(120))
        #expect(moved == [.updated(AlertSnapshot(signal: .cpu, severity: .amber, observation: .fraction(0.93)))])
        let red = evaluator.observe(.fraction(0.95), for: .cpu, at: at(130))
        #expect(red == [.updated(AlertSnapshot(signal: .cpu, severity: .red, observation: .fraction(0.95)))])
    }

    @Test("The deadline covers the hold end, the clear hold end and a deferred fire")
    func deadlines() {
        var evaluator = configured([rule(.cpu, hold: .oneMinute)])
        #expect(evaluator.nextDeadline() == nil)
        _ = evaluator.observe(.fraction(0.95), for: .cpu, at: at(100))
        #expect(evaluator.nextDeadline() == at(160))
        _ = evaluator.advance(to: at(160))
        #expect(evaluator.nextDeadline() == nil)
        _ = evaluator.observe(.fraction(0.5), for: .cpu, at: at(200))
        #expect(evaluator.nextDeadline() == at(230))
    }

    @Test("A memory pressure alert fires after its hold and clears after thirty seconds at normal")
    func memoryEndToEnd() {
        var evaluator = configured([rule(.memoryPressure, limit: 1, hold: .oneMinute)])
        _ = evaluator.observe(.pressure(.warning), for: .memoryPressure, at: at(100))
        let fired = evaluator.advance(to: at(160))
        #expect(fired == [.fired(AlertSnapshot(signal: .memoryPressure, severity: .amber, observation: .pressure(.warning)))])
        let worse = evaluator.observe(.pressure(.critical), for: .memoryPressure, at: at(170))
        #expect(worse == [.updated(AlertSnapshot(signal: .memoryPressure, severity: .red, observation: .pressure(.critical)))])
        _ = evaluator.observe(.pressure(.normal), for: .memoryPressure, at: at(200))
        #expect(evaluator.advance(to: at(230)) == [.cleared(.memoryPressure)])
    }
}
