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
}
