//
//  AutomationRule.swift
//  holzBar
//

import Foundation

/// The kind of power source.
nonisolated enum AutomationPowerSource: String, Codable, Sendable {
    case battery
    case adapter
}

/// A kind of network connection.
nonisolated enum AutomationNetworkKind: String, Codable, Sendable {
    case wifi
    case ethernet
    case offline
    /// A connection the system treats as expensive, such as a phone's hotspot.
    case expensive
    /// The traffic goes through a tunnel, as with a VPN that sends everything through it.
    case vpn
}

/// A span of the day on chosen weekdays.
///
/// The span runs from `startMinute` up to, but not including, `endMinute`, in minutes after
/// midnight. A span whose end is before its start runs overnight; its weekdays are those on
/// which it starts.
nonisolated struct AutomationTimeWindow: Codable, Equatable, Sendable {
    /// The first minute of the span, from 0 to 1439.
    var startMinute: Int
    /// The minute at which the span ends, from 0 to 1439.
    var endMinute: Int
    /// The weekdays on which the span starts, as `Calendar` numbers (1 is Sunday). Empty
    /// means every day.
    var weekdays: Set<Int>

    /// Returns a Boolean value that indicates whether a moment lies in the span.
    ///
    /// - Parameters:
    ///   - minuteOfDay: The minutes since midnight, from 0 to 1439.
    ///   - weekday: The weekday as a `Calendar` number.
    func contains(minuteOfDay: Int, weekday: Int) -> Bool {
        func runsOn(_ day: Int) -> Bool {
            weekdays.isEmpty || weekdays.contains(day)
        }
        if startMinute == endMinute {
            return false
        }
        if startMinute < endMinute {
            return minuteOfDay >= startMinute && minuteOfDay < endMinute && runsOn(weekday)
        }
        if minuteOfDay >= startMinute {
            return runsOn(weekday)
        }
        if minuteOfDay < endMinute {
            return runsOn(weekday == 1 ? 7 : weekday - 1)
        }
        return false
    }

    var isValid: Bool {
        (0..<1440).contains(startMinute)
            && (0..<1440).contains(endMinute)
            && weekdays.allSatisfy { (1...7).contains($0) }
    }
}

/// One condition of a rule.
nonisolated enum AutomationCondition: Codable, Equatable, Sendable {
    case power(AutomationPowerSource)
    case batteryBelow(Int)
    case lowPowerMode
    case appRunning(String)
    case appFrontmost(String)
    case time(AutomationTimeWindow)
    case displayConnected(String)
    case network(AutomationNetworkKind)
    case wifiNetwork(String)
    /// Another app uses a camera.
    case cameraInUse
    /// Another app records from the microphone.
    case microphoneInUse
    /// A script the user approved ends with status 0. The name is the file name in the scripts
    /// folder.
    case scriptSucceeds(String)

    /// Whether the condition holds, or `nil` when the facts it needs are unknown.
    func evaluate(in facts: AutomationFacts) -> Bool? {
        switch self {
        case .power(let source):
            return facts.powerSource.map { $0 == source }
        case .batteryBelow(let percent):
            return facts.batteryPercent.map { $0 < percent }
        case .lowPowerMode:
            return facts.isLowPowerMode
        case .appRunning(let bundleID):
            return facts.runningApps.map { $0.contains(bundleID) }
        case .appFrontmost(let bundleID):
            return facts.frontmostApp.map { $0 == bundleID }
        case .time(let window):
            guard let minute = facts.minuteOfDay, let weekday = facts.weekday else {
                return nil
            }
            return window.contains(minuteOfDay: minute, weekday: weekday)
        case .displayConnected(let uuid):
            return facts.connectedDisplays.map { $0.contains(uuid) }
        case .network(let kind):
            return facts.networkKinds.map { $0.contains(kind) }
        case .wifiNetwork(let name):
            return facts.wifiName.map { $0 == name }
        case .cameraInUse:
            return facts.isCameraInUse
        case .microphoneInUse:
            return facts.isMicrophoneInUse
        case .scriptSucceeds(let name):
            return facts.scriptResults[name]
        }
    }

    /// The kind of system event that can change the condition.
    var source: AutomationSource {
        switch self {
        case .power, .batteryBelow: .power
        case .lowPowerMode: .lowPowerMode
        case .appRunning: .runningApps
        case .appFrontmost: .frontmostApp
        case .time: .time
        case .displayConnected: .displays
        case .network: .network
        case .wifiNetwork: .wifi
        case .cameraInUse, .microphoneInUse: .capture
        case .scriptSucceeds: .scripts
        }
    }

    var isValid: Bool {
        switch self {
        case .batteryBelow(let percent):
            return (0...100).contains(percent)
        case .appRunning(let bundleID), .appFrontmost(let bundleID):
            return !bundleID.isEmpty && bundleID.utf8.count <= 255
        case .time(let window):
            return window.isValid
        case .displayConnected(let uuid):
            return !uuid.isEmpty && uuid.utf8.count <= 64
        case .wifiNetwork(let name):
            return !name.isEmpty && name.utf8.count <= 32
        case .scriptSucceeds(let name):
            return ScriptGate.isPlainName(name)
        case .power, .lowPowerMode, .network, .cameraInUse, .microphoneInUse:
            return true
        }
    }
}

/// A kind of system event. Each kind has one observer, which exists only while an enabled
/// rule has a condition of that kind.
nonisolated enum AutomationSource: CaseIterable, Hashable, Sendable {
    case power
    case lowPowerMode
    case runningApps
    case frontmostApp
    case time
    case displays
    case network
    case wifi
    /// Whether another app uses a camera or the microphone.
    case capture
    /// Scripts have no observer of their own: they are checked when other events arrive, and
    /// by the user's "Check now".
    case scripts
}

/// A condition with the choice to invert it.
nonisolated struct AutomationClause: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var condition: AutomationCondition
    var isNegated = false

    /// Whether the clause holds, or `nil` when the facts are unknown. An unknown fact stays
    /// unknown when negated.
    func evaluate(in facts: AutomationFacts) -> Bool? {
        condition.evaluate(in: facts).map { $0 != isNegated }
    }
}

/// The current answers to every question the conditions ask. A `nil` fact is unknown or not
/// available, for example the Wi-Fi name without Location Services.
nonisolated struct AutomationFacts: Equatable, Sendable {
    var powerSource: AutomationPowerSource?
    var batteryPercent: Int?
    var isLowPowerMode: Bool?
    var runningApps: Set<String>?
    var frontmostApp: String?
    /// Minutes since midnight, from 0 to 1439.
    var minuteOfDay: Int?
    /// A `Calendar` weekday number.
    var weekday: Int?
    var connectedDisplays: Set<String>?
    var networkKinds: Set<AutomationNetworkKind>?
    var wifiName: String?
    var isCameraInUse: Bool?
    var isMicrophoneInUse: Bool?
    /// What the approved scripts answered last, by file name. A script not in it is unknown.
    var scriptResults = [String: Bool]()
}

/// What a rule does when it becomes true.
nonisolated enum AutomationAction: Codable, Equatable, Sendable {
    case applyProfile(String)
    case showSection(AutomationSection)
    case zen(Bool)
    /// Keeps the Mac and its display from going to sleep on their own, or lets them.
    case keepAwake(Bool)
    /// Shows an item only while the rule holds and hides it in the given section otherwise.
    /// Unlike the other actions it is not acted on once: the item follows the condition.
    case showItemOnlyWhile(itemKey: String, hiding: AutomationSection)
    /// Runs an approved script once when the rule starts.
    case runScript(String)

    var isValid: Bool {
        switch self {
        case .applyProfile(let name):
            return !name.isEmpty && name.utf8.count <= 80
        case .showSection, .zen, .keepAwake:
            return true
        case .showItemOnlyWhile(let key, _):
            return !key.isEmpty && key.utf8.count <= 255
        case .runScript(let name):
            return ScriptGate.isPlainName(name)
        }
    }
}

/// A section of the menu bar that a rule can reveal.
nonisolated enum AutomationSection: String, Codable, Sendable {
    case hidden
    case alwaysHidden
}

/// How the clauses of a rule combine.
nonisolated enum AutomationMatch: String, Codable, Sendable {
    case all
    case any

    /// Combines the answers of the clauses. An unknown answer (`nil`) keeps the result
    /// unknown unless another answer decides it: one false answer makes "all" false, one true
    /// answer makes "any" true. No answers at all is unknown.
    func combine(_ results: [Bool?]) -> Bool? {
        guard !results.isEmpty else {
            return nil
        }
        switch self {
        case .all:
            if results.contains(false) {
                return false
            }
            return results.contains { $0 == nil } ? nil : true
        case .any:
            if results.contains(true) {
                return true
            }
            return results.contains { $0 == nil } ? nil : false
        }
    }
}

/// "When these things are true, do this."
nonisolated struct AutomationRule: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var isEnabled = true
    var match = AutomationMatch.all
    var clauses: [AutomationClause]
    var action: AutomationAction
    /// Whether the previous profile or Zen mode comes back when the rule stops being true.
    var restoresWhenEnded = true

    /// Whether the rule holds. A rule without clauses never holds; an unknown clause counts
    /// as not holding.
    func isMet(in facts: AutomationFacts) -> Bool {
        let results = clauses.map { $0.evaluate(in: facts) ?? false }
        guard !results.isEmpty else {
            return false
        }
        switch match {
        case .all: return results.allSatisfy { $0 }
        case .any: return results.contains(true)
        }
    }

    /// Whether the rule holds, or `nil` when the facts do not tell yet. A rule without clauses
    /// is unknown.
    func evaluation(in facts: AutomationFacts) -> Bool? {
        match.combine(clauses.map { $0.evaluate(in: facts) })
    }

    var isValid: Bool {
        !name.isEmpty
            && name.utf8.count <= 80
            && !clauses.isEmpty
            && clauses.count <= 10
            && clauses.allSatisfy { $0.condition.isValid }
            && action.isValid
    }

    /// The rules of a stored list without the ones that use a script. Scripts are local to
    /// the Mac and are never created or approved by an imported or synced file.
    static func removingScriptRules(from data: Data) -> Data? {
        guard let rules = try? JSONDecoder().decode([AutomationRule].self, from: data) else {
            return nil
        }
        return try? JSONEncoder().encode(rules.filter { !$0.usesScript })
    }

    /// The kinds of event the enabled rules need to observe.
    static func sources(of rules: [AutomationRule]) -> Set<AutomationSource> {
        Set(rules.filter(\.isEnabled).flatMap(\.clauses).map(\.condition.source))
    }

    /// The time spans of the enabled rules.
    static func timeWindows(of rules: [AutomationRule]) -> [AutomationTimeWindow] {
        rules.filter(\.isEnabled).flatMap(\.clauses).compactMap { clause -> AutomationTimeWindow? in
            guard case .time(let window) = clause.condition else {
                return nil
            }
            return window
        }
    }

    /// Whether the rule runs or asks a script.
    var usesScript: Bool {
        if case .runScript = action {
            return true
        }
        return clauses.contains { clause in
            if case .scriptSucceeds = clause.condition {
                return true
            }
            return false
        }
    }

    /// The most rules that are kept.
    static let maximumCount = 50

    /// The rules that pass validation, at most ``maximumCount``, in their order. Rules with
    /// a repeated identifier after the first are dropped.
    static func validated(_ rules: [AutomationRule]) -> [AutomationRule] {
        var seen = Set<UUID>()
        var result: [AutomationRule] = []
        for rule in rules where rule.isValid && seen.insert(rule.id).inserted {
            result.append(rule)
            if result.count == maximumCount {
                break
            }
        }
        return result
    }
}

/// When the next time span starts or ends.
nonisolated enum AutomationSchedule {
    /// The seconds from `secondsOfDay` (since midnight) to the next start or end of any of
    /// the windows, or `nil` without a window. Weekdays are not considered: the boundary
    /// of a day on which nothing changes only costs one wake-up.
    static func secondsUntilNextBoundary(of windows: [AutomationTimeWindow], from secondsOfDay: Double) -> Double? {
        let day = 86_400.0
        let boundaries = windows.flatMap { [$0.startMinute, $0.endMinute] }.map { Double($0) * 60 }
        return boundaries
            .map { boundary in
                let delta = boundary - secondsOfDay
                return delta > 0 ? delta : delta + day
            }
            .min()
    }
}

/// Where an item follows a rule of the kind "show it only while …".
nonisolated enum ItemVisibility {
    /// The section index the rule wants for its item now: 0 (visible) while the rule holds,
    /// the hiding section while it does not, and `nil` when the rule is off, not of this kind
    /// or the facts do not tell yet. The item then stays where it is: it is never hidden
    /// because a fact is unavailable.
    static func wantedSection(of rule: AutomationRule, facts: AutomationFacts) -> (itemKey: String, section: Int)? {
        guard rule.isEnabled, case .showItemOnlyWhile(let key, let hiding) = rule.action else {
            return nil
        }
        switch rule.evaluation(in: facts) {
        case .some(true): return (key, 0)
        case .some(false): return (key, hiding == .alwaysHidden ? 2 : 1)
        case .none: return nil
        }
    }
}
