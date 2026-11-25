import Testing
@testable import HolzBarCore

@Suite("AlertRequestPlan")
struct AlertRequestPlanTests {
    private func rule(_ signal: AlertSignal, on: Bool = true) -> ThresholdRule {
        var rule = ThresholdRule.defaultRule(for: signal)
        rule.isOn = on
        return rule
    }

    private var defaults: [ThresholdRule] {
        AlertSignal.allCases.map { ThresholdRule.defaultRule(for: $0) }
    }

    @Test("With the module off nothing is requested")
    func moduleOff() {
        #expect(AlertRequestPlan.request(rules: defaults, isModuleOn: false, hasBattery: true) == nil)
    }

    @Test("With every rule off nothing is requested")
    func everyRuleOff() {
        let rules = AlertSignal.allCases.map { rule($0, on: false) }
        #expect(AlertRequestPlan.request(rules: rules, isModuleOn: true, hasBattery: true) == nil)
        #expect(AlertRequestPlan.request(rules: [], isModuleOn: true, hasBattery: true) == nil)
    }

    @Test("The CPU rule alone reads the load every ten seconds and needs a baseline")
    func cpuOnly() {
        let request = AlertRequestPlan.request(rules: [rule(.cpu)], isModuleOn: true, hasBattery: true)
        #expect(request == ReadoutRequest(metrics: [.cpu], intervalSeconds: 10, needsBaseline: true))
    }

    @Test("The thermal rule alone follows its event and needs no baseline")
    func thermalOnly() {
        let request = AlertRequestPlan.request(rules: [rule(.thermal)], isModuleOn: true, hasBattery: true)
        #expect(request == ReadoutRequest(metrics: [.thermal], intervalSeconds: 60, needsBaseline: false))
    }

    @Test("The defaults with a battery read the CPU, the thermal state, the disk space and the power")
    func defaultsWithBattery() {
        let request = AlertRequestPlan.request(rules: defaults, isModuleOn: true, hasBattery: true)
        #expect(request == ReadoutRequest(metrics: [.cpu, .thermal, .diskSpace, .power], intervalSeconds: 10, needsBaseline: true))
    }

    @Test("Without a battery the battery rule reads nothing")
    func defaultsWithoutBattery() {
        let request = AlertRequestPlan.request(rules: defaults, isModuleOn: true, hasBattery: false)
        #expect(request?.metrics == [.cpu, .thermal, .diskSpace])
        #expect(AlertRequestPlan.request(rules: [rule(.macBattery)], isModuleOn: true, hasBattery: false) == nil)
    }

    @Test("A memory pressure rule reads the pressure, and the disk rule alone reads once a minute")
    func memoryAndDisk() {
        let memory = AlertRequestPlan.request(rules: [rule(.memoryPressure)], isModuleOn: true, hasBattery: false)
        #expect(memory?.metrics == [.memoryPressure])
        let disk = AlertRequestPlan.request(rules: [rule(.freeDisk)], isModuleOn: true, hasBattery: false)
        #expect(disk == ReadoutRequest(metrics: [.diskSpace], intervalSeconds: 60, needsBaseline: false))
    }

    @Test("Every signal has its own metric")
    func metrics() {
        #expect(AlertRequestPlan.metric(for: .cpu) == .cpu)
        #expect(AlertRequestPlan.metric(for: .memoryPressure) == .memoryPressure)
        #expect(AlertRequestPlan.metric(for: .thermal) == .thermal)
        #expect(AlertRequestPlan.metric(for: .freeDisk) == .diskSpace)
        #expect(AlertRequestPlan.metric(for: .macBattery) == .power)
    }

    @Test("The alerts consumer is the one background consumer, and leaves the ledger idle when it goes")
    func idleAfterwards() throws {
        var ledger = ReadoutLedger()
        let request = AlertRequestPlan.request(rules: defaults, isModuleOn: true, hasBattery: true)
        let unwrapped = try #require(request)
        ledger.register(AlertRequestPlan.consumerID, kind: .background, request: unwrapped)
        #expect(!ledger.isIdle)
        #expect(ledger.backgroundCount == 1)
        #expect(ledger.visibleCount == 0)
        ledger.unregister(AlertRequestPlan.consumerID)
        #expect(ledger.isIdle)
        let now = ContinuousClock.now
        #expect(ReadoutSchedule.nextTick(ledger: ledger, deliveries: [:], now: now, isLowPowerMode: false, isPaused: false) == nil)
        #expect(ReadoutSchedule.observers(ledger: ledger, isPaused: false).isEmpty)
    }

    @Test("A request of the alerts is a background consumer that ticks while a rule is on")
    func ticksWhileOn() throws {
        var ledger = ReadoutLedger()
        let request = AlertRequestPlan.request(rules: [rule(.cpu)], isModuleOn: true, hasBattery: false)
        ledger.register(AlertRequestPlan.consumerID, kind: .background, request: try #require(request))
        let now = ContinuousClock.now
        let tick = ReadoutSchedule.nextTick(ledger: ledger, deliveries: [:], now: now, isLowPowerMode: false, isPaused: false)
        #expect(tick?.consumers == [AlertRequestPlan.consumerID])
        // The Mac rests: nothing is read.
        #expect(ReadoutSchedule.nextTick(ledger: ledger, deliveries: [:], now: now, isLowPowerMode: false, isPaused: true) == nil)
    }
}
