//
//  AutomationDescription.swift
//  holzBar
//

import AppKit

/// Says in words what a rule does, in the user's language.
enum AutomationDescription {
    /// The rule as one sentence.
    static func sentence(for rule: AutomationRule) -> String {
        guard !rule.clauses.isEmpty else {
            return String(localized: "Add a condition to this rule.")
        }
        let parts = rule.clauses.map { text(for: $0.condition) }
        let conditions = switch rule.match {
        case .all: parts.formatted(.list(type: .and))
        case .any: parts.formatted(.list(type: .or))
        }
        return String(localized: "When \(conditions), \(text(for: rule.action)).")
    }

    /// A condition as the part of a sentence that follows "When".
    static func text(for condition: AutomationCondition) -> String {
        switch condition {
        case .power(.battery):
            String(localized: "the Mac runs on battery")
        case .power(.adapter):
            String(localized: "the Mac is plugged in")
        case .batteryBelow(let percent):
            String(localized: "the battery is below \((Double(percent) / 100).formatted(.percent))")
        case .lowPowerMode:
            String(localized: "Low Power Mode is on")
        case .appRunning(let bundleID):
            String(localized: "\(applicationName(for: bundleID)) is running")
        case .appFrontmost(let bundleID):
            String(localized: "\(applicationName(for: bundleID)) is in front")
        case .time(let window):
            timeText(for: window)
        case .displayConnected(let uuid):
            String(localized: "the display “\(displayName(for: uuid))” is connected")
        case .network(.wifi):
            String(localized: "the Mac is connected through Wi-Fi")
        case .network(.ethernet):
            String(localized: "the Mac is connected through Ethernet")
        case .network(.offline):
            String(localized: "the Mac is offline")
        case .network(.vpn):
            String(localized: "the traffic goes through a VPN")
        case .network(.expensive):
            String(localized: "the connection is expensive, for example a hotspot")
        case .wifiNetwork(let name):
            String(localized: "the Wi-Fi network is “\(name)”")
        }
    }

    /// An action as the part of a sentence that follows the comma.
    static func text(for action: AutomationAction) -> String {
        switch action {
        case .applyProfile(let name):
            String(localized: "apply the profile “\(name)”")
        case .showSection(.hidden):
            String(localized: "show the hidden section")
        case .showSection(.alwaysHidden):
            String(localized: "show the always-hidden section")
        case .zen(true):
            String(localized: "turn Zen mode on")
        case .zen(false):
            String(localized: "turn Zen mode off")
        case .keepAwake(true):
            String(localized: "keep the Mac awake")
        case .keepAwake(false):
            String(localized: "let the Mac sleep")
        }
    }

    private static func timeText(for window: AutomationTimeWindow) -> String {
        let start = time(minutes: window.startMinute).formatted(date: .omitted, time: .shortened)
        let end = time(minutes: window.endMinute).formatted(date: .omitted, time: .shortened)
        if window.weekdays.isEmpty {
            return String(localized: "it is between \(start) and \(end)")
        }
        let symbols = Calendar.current.shortWeekdaySymbols
        let days = window.weekdays.sorted().compactMap { day in
            symbols.indices.contains(day - 1) ? symbols[day - 1] : nil
        }
        return String(localized: "it is between \(start) and \(end) on \(days.formatted(.list(type: .and)))")
    }

    /// A moment today at the given minute of the day, for formatting.
    static func time(minutes: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    /// The name of an application, or its bundle identifier when it is not installed.
    static func applicationName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// The name of a display, or a note when it is not connected now.
    static func displayName(for uuid: String) -> String {
        let screen = NSScreen.screens.first { Bridging.getDisplayUUIDString(for: $0.displayID) == uuid }
        return screen?.localizedName ?? String(localized: "not connected")
    }
}
