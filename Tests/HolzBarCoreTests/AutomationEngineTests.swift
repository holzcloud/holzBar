import Foundation
import Testing
@testable import HolzBarCore

@Suite("AutomationEngine")
struct AutomationEngineTests {
    private typealias Engine = AutomationEngine

    private func rule(
        _ name: String,
        _ conditions: [AutomationCondition],
        match: AutomationMatch = .all,
        action: AutomationAction,
        restores: Bool = true
    ) -> AutomationRule {
        AutomationRule(
            name: name,
            match: match,
            clauses: conditions.map { AutomationClause(condition: $0) },
            action: action,
            restoresWhenEnded: restores
        )
    }

    private let office = AutomationCondition.displayConnected("DISPLAY-1")
    private let battery = AutomationCondition.power(.battery)

    private func facts(
        displays: Set<String> = [],
        power: AutomationPowerSource = .adapter
    ) -> AutomationFacts {
        AutomationFacts(powerSource: power, connectedDisplays: displays)
    }

    private func run(
        _ rules: [AutomationRule],
        _ facts: AutomationFacts,
        profile: String? = "Home",
        zen: Bool = false,
        state: Engine.State = Engine.State()
    ) -> Engine.Result {
        Engine.evaluate(
            rules: rules,
            facts: facts,
            context: Engine.Context(currentProfile: profile, isZenOn: zen),
            state: state
        )
    }

    @Test("A rule acts once when it becomes true, not while it stays true")
    func actsOnce() {
        let rules = [rule("Office", [office], action: .applyProfile("Office"))]
        let first = run(rules, facts(displays: ["DISPLAY-1"]))
        #expect(first.effects == [.applyProfile("Office")])
        let second = run(rules, facts(displays: ["DISPLAY-1"]), profile: "Home", state: first.state)
        #expect(second.effects.isEmpty)
    }

    @Test("A rule that is not true does nothing")
    func staysQuiet() {
        let rules = [rule("Office", [office], action: .applyProfile("Office"))]
        #expect(run(rules, facts()).effects.isEmpty)
    }

    @Test("The previous profile comes back when the rule ends")
    func restoresPrevious() {
        let rules = [rule("Office", [office], action: .applyProfile("Office"))]
        let started = run(rules, facts(displays: ["DISPLAY-1"]), profile: "Home")
        let ended = run(rules, facts(), profile: "Office", state: started.state)
        #expect(ended.effects == [.applyProfile("Home")])
        #expect(ended.state.active.isEmpty)
        #expect(ended.state.undo.isEmpty)
    }

    @Test("The previous profile stays away when the rule is told not to restore")
    func keepsWhenAsked() {
        let rules = [rule("Office", [office], action: .applyProfile("Office"), restores: false)]
        let started = run(rules, facts(displays: ["DISPLAY-1"]))
        let ended = run(rules, facts(), profile: "Office", state: started.state)
        #expect(ended.effects.isEmpty)
    }

    @Test("The user's own change in the meantime is not overwritten")
    func respectsUserChange() {
        let rules = [rule("Office", [office], action: .applyProfile("Office"))]
        let started = run(rules, facts(displays: ["DISPLAY-1"]))
        let ended = run(rules, facts(), profile: "Travel", state: started.state)
        #expect(ended.effects.isEmpty)
    }

    @Test("The profile that is already applied is not applied again")
    func skipsActiveProfile() {
        let rules = [rule("Office", [office], action: .applyProfile("Office"))]
        let result = run(rules, facts(displays: ["DISPLAY-1"]), profile: "Office")
        #expect(result.effects.isEmpty)
        #expect(result.state.active.count == 1)
        #expect(result.state.undo.isEmpty)
    }

    @Test("All clauses must hold, or any of them")
    func allAndAny() {
        let clauses = [office, battery]
        let all = [rule("All", clauses, action: .zen(true))]
        let any = [rule("Any", clauses, match: .any, action: .zen(true))]
        let onlyDisplay = facts(displays: ["DISPLAY-1"])
        #expect(run(all, onlyDisplay).effects.isEmpty)
        #expect(run(any, onlyDisplay).effects == [.setZen(true)])
        #expect(run(all, facts(displays: ["DISPLAY-1"], power: .battery)).effects == [.setZen(true)])
    }

    @Test("Zen mode returns to what it was")
    func zenRestores() {
        let rules = [rule("Battery", [battery], action: .zen(true))]
        let started = run(rules, facts(power: .battery))
        #expect(started.effects == [.setZen(true)])
        let ended = run(rules, facts(), zen: true, state: started.state)
        #expect(ended.effects == [.setZen(false)])
    }

    @Test("Keeping the Mac awake is undone when the rule ends")
    func keepAwakeRestores() {
        let rules = [rule("Power", [battery], action: .keepAwake(true))]
        let started = run(rules, facts(power: .battery))
        #expect(started.effects == [.setKeepAwake(true)])
        let ended = Engine.evaluate(
            rules: rules,
            facts: facts(),
            context: Engine.Context(currentProfile: "Home", isZenOn: false, isKeepAwakeOn: true),
            state: started.state
        )
        #expect(ended.effects == [.setKeepAwake(false)])
    }

    @Test("A Mac that is already kept awake needs no new effect")
    func keepAwakeAlreadyOn() {
        let rules = [rule("Power", [battery], action: .keepAwake(true))]
        let result = Engine.evaluate(
            rules: rules,
            facts: facts(power: .battery),
            context: Engine.Context(currentProfile: nil, isZenOn: false, isKeepAwakeOn: true),
            state: Engine.State()
        )
        #expect(result.effects.isEmpty)
        #expect(result.state.undo.isEmpty)
    }

    @Test("The VPN condition reads the network kinds")
    func vpnCondition() {
        let vpn = AutomationCondition.network(.vpn)
        #expect(vpn.evaluate(in: AutomationFacts(networkKinds: [.wifi, .vpn])) == true)
        #expect(vpn.evaluate(in: AutomationFacts(networkKinds: [.wifi])) == false)
        #expect(vpn.evaluate(in: AutomationFacts()) == nil)
    }

    @Test("The first rule that applies a profile wins; the other waits")
    func firstProfileWins() {
        let rules = [
            rule("A", [office], action: .applyProfile("A")),
            rule("B", [office], action: .applyProfile("B")),
        ]
        let first = run(rules, facts(displays: ["DISPLAY-1"]))
        #expect(first.effects == [.applyProfile("A")])
        #expect(first.state.active == [rules[0].id])
        // Once the first is gone, its change is undone and the second may act.
        let withoutFirst = [rules[1]]
        let later = run(withoutFirst, facts(displays: ["DISPLAY-1"]), profile: "A", state: first.state)
        #expect(later.effects == [.applyProfile("Home"), .applyProfile("B")])
    }

    @Test("A removed or disabled rule ends like a rule that stopped being true")
    func removedRuleEnds() {
        var rules = [rule("Office", [office], action: .applyProfile("Office"))]
        let started = run(rules, facts(displays: ["DISPLAY-1"]))
        rules[0].isEnabled = false
        let ended = run(rules, facts(displays: ["DISPLAY-1"]), profile: "Office", state: started.state)
        #expect(ended.effects == [.applyProfile("Home")])
    }

    @Test("An unknown fact never makes a clause true, even when negated")
    func unknownFacts() {
        let wifi = AutomationCondition.wifiNetwork("Home")
        let plain = AutomationClause(condition: wifi)
        let negated = AutomationClause(condition: wifi, isNegated: true)
        let unknown = AutomationFacts()
        #expect(plain.evaluate(in: unknown) == nil)
        #expect(negated.evaluate(in: unknown) == nil)
        #expect(plain.evaluate(in: AutomationFacts(wifiName: "Home")) == true)
        #expect(negated.evaluate(in: AutomationFacts(wifiName: "Home")) == false)
        #expect(negated.evaluate(in: AutomationFacts(wifiName: "Cafe")) == true)
    }

    @Test("A rule without clauses never holds")
    func emptyRule() {
        let empty = rule("Empty", [], action: .zen(true))
        #expect(!empty.isMet(in: facts()))
        #expect(!empty.isValid)
    }

    @Test("A time span inside one day")
    func daytimeWindow() {
        let window = AutomationTimeWindow(startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [2, 3, 4, 5, 6])
        #expect(window.contains(minuteOfDay: 9 * 60, weekday: 2))
        #expect(window.contains(minuteOfDay: 16 * 60 + 59, weekday: 6))
        #expect(!window.contains(minuteOfDay: 17 * 60, weekday: 2))
        #expect(!window.contains(minuteOfDay: 12 * 60, weekday: 1))
    }

    @Test("A time span over midnight belongs to the day it starts")
    func overnightWindow() {
        let window = AutomationTimeWindow(startMinute: 22 * 60, endMinute: 6 * 60, weekdays: [6])
        #expect(window.contains(minuteOfDay: 23 * 60, weekday: 6))
        #expect(window.contains(minuteOfDay: 2 * 60, weekday: 7))
        #expect(!window.contains(minuteOfDay: 2 * 60, weekday: 6))
        #expect(!window.contains(minuteOfDay: 23 * 60, weekday: 7))
        let sundayMorning = AutomationTimeWindow(startMinute: 22 * 60, endMinute: 6 * 60, weekdays: [7])
        #expect(sundayMorning.contains(minuteOfDay: 60, weekday: 1))
    }

    @Test("Without weekdays a span runs every day; an empty span never")
    func everyDay() {
        let window = AutomationTimeWindow(startMinute: 60, endMinute: 120, weekdays: [])
        #expect(window.contains(minuteOfDay: 90, weekday: 4))
        let empty = AutomationTimeWindow(startMinute: 60, endMinute: 60, weekdays: [])
        #expect(!empty.contains(minuteOfDay: 60, weekday: 4))
    }

    @Test("Every kind of condition reads its own fact")
    func conditionKinds() {
        let facts = AutomationFacts(
            powerSource: .battery,
            batteryPercent: 15,
            isLowPowerMode: true,
            runningApps: ["com.example.a"],
            frontmostApp: "com.example.b",
            minuteOfDay: 600,
            weekday: 3,
            connectedDisplays: ["D"],
            networkKinds: [.wifi, .expensive],
            wifiName: "Home"
        )
        #expect(AutomationCondition.power(.battery).evaluate(in: facts) == true)
        #expect(AutomationCondition.power(.adapter).evaluate(in: facts) == false)
        #expect(AutomationCondition.batteryBelow(20).evaluate(in: facts) == true)
        #expect(AutomationCondition.batteryBelow(15).evaluate(in: facts) == false)
        #expect(AutomationCondition.lowPowerMode.evaluate(in: facts) == true)
        #expect(AutomationCondition.appRunning("com.example.a").evaluate(in: facts) == true)
        #expect(AutomationCondition.appFrontmost("com.example.a").evaluate(in: facts) == false)
        #expect(AutomationCondition.displayConnected("D").evaluate(in: facts) == true)
        #expect(AutomationCondition.network(.ethernet).evaluate(in: facts) == false)
        #expect(AutomationCondition.network(.expensive).evaluate(in: facts) == true)
        #expect(AutomationCondition.wifiNetwork("Home").evaluate(in: facts) == true)
    }

    @Test("A rule survives a JSON round trip")
    func codable() throws {
        let original = rule(
            "Night",
            [
                .time(AutomationTimeWindow(startMinute: 1320, endMinute: 360, weekdays: [1, 7])),
                .appRunning("com.example.a"),
            ],
            match: .any,
            action: .showSection(.alwaysHidden)
        )
        let data = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([AutomationRule].self, from: data)
        #expect(decoded == [original])
    }

    @Test("Validation drops rules out of range and keeps at most fifty")
    func validation() {
        let good = rule("Good", [.batteryBelow(20)], action: .zen(true))
        let badBattery = rule("Bad", [.batteryBelow(120)], action: .zen(true))
        let badName = rule("", [.lowPowerMode], action: .zen(true))
        let longSSID = rule("Long", [.wifiNetwork(String(repeating: "a", count: 33))], action: .zen(true))
        let badProfile = rule("Profile", [.lowPowerMode], action: .applyProfile(""))
        let validated = AutomationRule.validated([good, badBattery, badName, longSSID, badProfile, good])
        #expect(validated == [good])

        let many = (0..<60).map { rule("Rule \($0)", [.lowPowerMode], action: .zen(true)) }
        #expect(AutomationRule.validated(many).count == AutomationRule.maximumCount)
    }

    @Test("The observers needed are those of the enabled rules")
    func neededSources() {
        var timeRule = rule(
            "Time",
            [.time(AutomationTimeWindow(startMinute: 60, endMinute: 120, weekdays: []))],
            action: .zen(true)
        )
        let powerRule = rule("Power", [battery, .batteryBelow(20)], action: .zen(true))
        #expect(AutomationRule.sources(of: [timeRule, powerRule]) == [.time, .power])
        timeRule.isEnabled = false
        #expect(AutomationRule.sources(of: [timeRule, powerRule]) == [.power])
        #expect(AutomationRule.sources(of: []).isEmpty)
        #expect(AutomationRule.timeWindows(of: [timeRule, powerRule]).isEmpty)
    }

    @Test("The next boundary is the nearest start or end, wrapping past midnight")
    func nextBoundary() {
        let windows = [AutomationTimeWindow(startMinute: 9 * 60, endMinute: 17 * 60, weekdays: [])]
        #expect(AutomationSchedule.secondsUntilNextBoundary(of: windows, from: 8 * 3600) == 3600.0)
        #expect(AutomationSchedule.secondsUntilNextBoundary(of: windows, from: 12 * 3600) == 5.0 * 3600)
        #expect(AutomationSchedule.secondsUntilNextBoundary(of: windows, from: 17 * 3600) == 16.0 * 3600)
        #expect(AutomationSchedule.secondsUntilNextBoundary(of: [], from: 0) == nil)
    }

    @Test("Answers combine with unknown ones staying unknown unless another decides")
    func combine() {
        #expect(AutomationMatch.all.combine([true, true]) == true)
        #expect(AutomationMatch.all.combine([true, nil]) == nil)
        #expect(AutomationMatch.all.combine([false, nil]) == false)
        #expect(AutomationMatch.any.combine([false, nil]) == nil)
        #expect(AutomationMatch.any.combine([true, nil]) == true)
        #expect(AutomationMatch.any.combine([false, false]) == false)
        #expect(AutomationMatch.all.combine([]) == nil)
    }

    @Test("An item follows its rule: visible while it holds, hidden otherwise, still when unknown")
    func itemFollowsRule() throws {
        let rule = rule(
            "VPN item",
            [.network(.vpn)],
            action: .showItemOnlyWhile(itemKey: "com.example.vpn:VPN", hiding: .alwaysHidden)
        )
        let holds = try #require(ItemVisibility.wantedSection(of: rule, facts: AutomationFacts(networkKinds: [.vpn])))
        #expect(holds.itemKey == "com.example.vpn:VPN" && holds.section == 0)
        let fails = try #require(ItemVisibility.wantedSection(of: rule, facts: AutomationFacts(networkKinds: [.wifi])))
        #expect(fails.section == 2)
        #expect(ItemVisibility.wantedSection(of: rule, facts: AutomationFacts()) == nil)
        var off = rule
        off.isEnabled = false
        #expect(ItemVisibility.wantedSection(of: off, facts: AutomationFacts(networkKinds: [.vpn])) == nil)
    }

    @Test("The engine leaves rules that follow a condition to the item logic")
    func engineSkipsItemRules() {
        let rule = rule(
            "Item",
            [battery],
            action: .showItemOnlyWhile(itemKey: "com.example.app:Item", hiding: .hidden)
        )
        let result = run([rule], facts(power: .battery))
        #expect(result.effects.isEmpty)
        #expect(result.state.active.isEmpty)
        #expect(rule.isValid)
        #expect(!AutomationAction.showItemOnlyWhile(itemKey: "", hiding: .hidden).isValid)
    }
}
