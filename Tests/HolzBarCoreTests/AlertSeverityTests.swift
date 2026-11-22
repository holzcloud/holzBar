import Testing
@testable import HolzBarCore

@Suite("AlertSeverity")
struct AlertSeverityTests {
    private func cpu(_ limit: Int) -> ThresholdRule {
        ThresholdRule(signal: .cpu, isOn: true, limit: limit, hold: .fiveMinutes)
    }

    @Test("CPU load is amber until the midpoint between the threshold and 100 %, then red")
    func cpuSeverity() {
        let rule = cpu(90)
        #expect(AlertSeverity.of(.fraction(0.91), rule: rule) == .amber)
        #expect(AlertSeverity.of(.fraction(0.94), rule: rule) == .amber)
        #expect(AlertSeverity.of(.fraction(0.95), rule: rule) == .red)
        #expect(AlertSeverity.of(.fraction(1.0), rule: rule) == .red)
    }

    @Test("At a threshold of 50 the red midpoint is 75")
    func cpuMidpointAtFifty() {
        let rule = cpu(50)
        #expect(AlertSeverity.of(.fraction(0.74), rule: rule) == .amber)
        #expect(AlertSeverity.of(.fraction(0.75), rule: rule) == .red)
    }

    @Test("A CPU alert has the cpu symbol, a priority of 25 and a red tint when red")
    func cpuLook() {
        let snapshot = AlertSnapshot(signal: .cpu, severity: .amber, observation: .fraction(0.92))
        #expect(AlertLook.symbol(for: snapshot) == "cpu")
        #expect(AlertLook.priority(for: .cpu) == 25)
        #expect(AlertLook.tint(for: .red) == .red)
        #expect(AlertLook.tint(for: .amber) == .amber)
    }

    @Test("The module and the test alert have their fixed names")
    func fixedNames() {
        #expect(AlertLook.moduleID == "system-alerts")
        #expect(AlertLook.testID == "test")
        #expect(AlertLook.testPercent == 92)
        #expect(AlertLook.testSymbol == "cpu")
        #expect(AlertLook.recoveredSymbol == "checkmark.circle")
        #expect(AlertLook.recoveredTint == .green)
    }

    @Test("Free disk space is amber below the threshold and red at half of it or less")
    func diskSeverity() {
        let rule = ThresholdRule(signal: .freeDisk, isOn: true, limit: 10, hold: .oneMinute)
        #expect(AlertSeverity.of(.freeBytes(9_000_000_000), rule: rule) == .amber)
        #expect(AlertSeverity.of(.freeBytes(5_000_001_000), rule: rule) == .amber)
        #expect(AlertSeverity.of(.freeBytes(5_000_000_000), rule: rule) == .red)
        #expect(AlertSeverity.of(.freeBytes(0), rule: rule) == .red)
        #expect(AlertSeverity.of(.freeBytes(Int64.max), rule: rule) == .amber)
    }

    @Test("The Mac battery is amber below the threshold and red at half of it or less")
    func batterySeverity() {
        let rule = ThresholdRule(signal: .macBattery, isOn: true, limit: 20, hold: .immediately)
        #expect(AlertSeverity.of(.battery(percent: 19, onBattery: true), rule: rule) == .amber)
        #expect(AlertSeverity.of(.battery(percent: 11, onBattery: true), rule: rule) == .amber)
        #expect(AlertSeverity.of(.battery(percent: 10, onBattery: true), rule: rule) == .red)
        #expect(AlertSeverity.of(.battery(percent: 0, onBattery: true), rule: rule) == .red)
    }

    @Test("A level is red at Critical and amber below it")
    func levelSeverity() {
        let memory = ThresholdRule(signal: .memoryPressure, isOn: true, limit: 1, hold: .oneMinute)
        #expect(AlertSeverity.of(.pressure(.warning), rule: memory) == .amber)
        #expect(AlertSeverity.of(.pressure(.critical), rule: memory) == .red)
        let thermal = ThresholdRule(signal: .thermal, isOn: true, limit: 1, hold: .immediately)
        #expect(AlertSeverity.of(.thermal(.fair), rule: thermal) == .amber)
        #expect(AlertSeverity.of(.thermal(.serious), rule: thermal) == .amber)
        #expect(AlertSeverity.of(.thermal(.critical), rule: thermal) == .red)
    }

    @Test("Every signal has its symbol; the thermometer follows the state and the battery the severity")
    func symbols() {
        func symbol(_ signal: AlertSignal, _ severity: AlertSeverity, _ observation: AlertObservation) -> String {
            AlertLook.symbol(for: AlertSnapshot(signal: signal, severity: severity, observation: observation))
        }
        #expect(symbol(.memoryPressure, .amber, .pressure(.warning)) == "memorychip")
        #expect(symbol(.thermal, .amber, .thermal(.fair)) == "thermometer.medium")
        #expect(symbol(.thermal, .amber, .thermal(.serious)) == "thermometer.high")
        #expect(symbol(.thermal, .red, .thermal(.critical)) == "thermometer.high")
        #expect(symbol(.freeDisk, .amber, .freeBytes(1)) == "internaldrive")
        #expect(symbol(.macBattery, .amber, .battery(percent: 18, onBattery: true)) == "battery.25percent")
        #expect(symbol(.macBattery, .red, .battery(percent: 8, onBattery: true)) == "battery.0percent")
    }

    @Test("Thermal state and the Mac battery rank above the other signals")
    func priorities() {
        #expect(AlertLook.priority(for: .thermal) == 30)
        #expect(AlertLook.priority(for: .macBattery) == 30)
        #expect(AlertLook.priority(for: .cpu) == 25)
        #expect(AlertLook.priority(for: .memoryPressure) == 25)
        #expect(AlertLook.priority(for: .freeDisk) == 25)
    }

    @Test("The short value is a number, an amount or a word, never a name")
    func shortValues() {
        #expect(AlertLook.shortValue(of: .fraction(0.924)) == .percent(92))
        #expect(AlertLook.shortValue(of: .fraction(.nan)) == nil)
        #expect(AlertLook.shortValue(of: .battery(percent: 18, onBattery: true)) == .percent(18))
        #expect(AlertLook.shortValue(of: .freeBytes(8_000_000_000)) == .bytes(8_000_000_000))
        #expect(AlertLook.shortValue(of: .pressure(.critical)) == .pressure(.critical))
        #expect(AlertLook.shortValue(of: .thermal(.serious)) == .thermal(.serious))
        #expect(AlertLook.shortValue(of: .unavailable) == nil)
    }
}
