import Testing
@testable import HolzBarCore

@Suite("LegacyRevealRules")
struct LegacyRevealRulesTests {
    private func rules(_ stored: [String: Any]) -> [AutomationRule] {
        LegacyRevealRules.rules(from: stored, batteryName: "Battery", offlineName: "Offline")
    }

    @Test("Settings that were off make no rule")
    func offMakesNoRule() {
        #expect(rules([:]).isEmpty)
        #expect(rules(["LowBattery": false, "Offline": false, "LowBatteryThreshold": 30]).isEmpty)
    }

    @Test("The low-battery rule asks for the battery and the level")
    func batteryRule() throws {
        let rule = try #require(rules(["LowBattery": true, "LowBatteryThreshold": 30]).first)
        #expect(rule.name == "Battery")
        #expect(rule.isEnabled)
        #expect(rule.match == .all)
        #expect(rule.clauses.map(\.condition) == [.power(.battery), .batteryBelow(30)])
        #expect(rule.action == .showSection(.hidden))
        #expect(rule.isValid)
    }

    @Test("The level defaults to 20 and stays within the old stepper's range")
    func batteryLevelRange() {
        #expect(rules(["LowBattery": true]).first?.clauses.last?.condition == .batteryBelow(20))
        #expect(rules(["LowBattery": true, "LowBatteryThreshold": 1]).first?.clauses.last?.condition == .batteryBelow(5))
        #expect(rules(["LowBattery": true, "LowBatteryThreshold": 90]).first?.clauses.last?.condition == .batteryBelow(50))
    }

    @Test("The offline rule asks for no connection")
    func offlineRule() throws {
        let rule = try #require(rules(["Offline": true]).first)
        #expect(rule.name == "Offline")
        #expect(rule.clauses.map(\.condition) == [.network(.offline)])
        #expect(rule.action == .showSection(.hidden))
        #expect(rule.isValid)
    }

    @Test("Both settings make two rules, battery first")
    func bothRules() {
        #expect(rules(["LowBattery": true, "Offline": true]).map(\.name) == ["Battery", "Offline"])
    }

    @Test("A value of the wrong type counts as off")
    func wrongTypes() {
        #expect(rules(["LowBattery": "yes", "Offline": 1]).isEmpty)
    }
}
