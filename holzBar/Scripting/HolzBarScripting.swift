//
//  HolzBarScripting.swift
//  holzBar
//

import AppKit

// holzBar's AppleScript dictionary (`Resources/holzBar.sdef`).
//
// A script can show, hide and toggle a section, apply a profile, turn a rule on or off and
// turn Zen mode on or off, and read a few names. It cannot create, change or delete a rule, a
// profile, a script or a setting, and it cannot touch scripts at all. Every command is turned
// into the same `URLCommand` that `holzbar://` URLs use, so it gets the same decision: lasting
// changes ask the user first, nothing reveals hidden items while Zen mode is on, and Zen mode
// does not end while the screen is shared (T-13-M1). holzBar sends no Apple events itself.

/// The base of the commands of the dictionary. A subclass names the URL command it stands for.
@objc(HolzBarScriptCommand)
nonisolated class HolzBarScriptCommand: NSScriptCommand {
    /// The command to hand to the URL command path, given the direct parameter.
    func urlCommand(for parameter: String?) -> URLCommand? {
        nil
    }

    override func performDefaultImplementation() -> Any? {
        let command = urlCommand(for: directParameter as? String)
        // Apple events arrive on the main thread.
        let failure: (number: Int, message: String)? = MainActor.assumeIsolated {
            guard let appState = AppState.current, appState.isSetUp else {
                return (-1708, String(localized: "holzBar is not ready yet."))
            }
            guard let command else {
                return (-1708, String(localized: "holzBar does not know that command."))
            }
            if let message = Self.unknownTarget(of: command, appState: appState) {
                return (-1728, message)
            }
            URLCommands.perform(command, appState: appState)
            return nil
        }
        if let failure {
            fail(number: failure.number, message: failure.message)
        }
        return nil
    }

    /// Why the command names something that does not exist, if it does. A script gets an
    /// error for a profile or a rule that is not there; a URL is ignored.
    @MainActor
    private static func unknownTarget(of command: URLCommand, appState: AppState) -> String? {
        switch command.action {
        case .applyProfile(let name):
            appState.profiles.profile(named: name) == nil ? String(localized: "There is no layout profile with that name.") : nil
        case .automationRule(let name, _):
            appState.automation.rule(named: name) == nil ? String(localized: "There is no automation rule with that name.") : nil
        default:
            nil
        }
    }

    private func fail(number: Int, message: String) {
        scriptErrorNumber = number
        scriptErrorString = message
    }
}

@objc(HolzBarSectionCommand)
nonisolated class HolzBarSectionCommand: HolzBarScriptCommand {
    var verb: String { "toggle" }

    override func urlCommand(for parameter: String?) -> URLCommand? {
        let name = parameter?.lowercased().replacingOccurrences(of: " ", with: "-") ?? "hidden"
        guard ["hidden", "always-hidden"].contains(name) else {
            return nil
        }
        return URLCommand(name: verb, arguments: [name])
    }
}

@objc(HolzBarShowSectionCommand)
nonisolated final class HolzBarShowSectionCommand: HolzBarSectionCommand {
    override var verb: String { "show" }
}

@objc(HolzBarHideSectionCommand)
nonisolated final class HolzBarHideSectionCommand: HolzBarSectionCommand {
    override var verb: String { "hide" }
}

@objc(HolzBarToggleSectionCommand)
nonisolated final class HolzBarToggleSectionCommand: HolzBarSectionCommand {}

@objc(HolzBarApplyProfileCommand)
nonisolated final class HolzBarApplyProfileCommand: HolzBarScriptCommand {
    override func urlCommand(for parameter: String?) -> URLCommand? {
        parameter.flatMap { $0.isEmpty ? nil : URLCommand(name: "profile", arguments: [$0]) }
    }
}

@objc(HolzBarEnableRuleCommand)
nonisolated final class HolzBarEnableRuleCommand: HolzBarScriptCommand {
    override func urlCommand(for parameter: String?) -> URLCommand? {
        parameter.flatMap { $0.isEmpty ? nil : URLCommand(name: "automation", arguments: ["enable", $0]) }
    }
}

@objc(HolzBarDisableRuleCommand)
nonisolated final class HolzBarDisableRuleCommand: HolzBarScriptCommand {
    override func urlCommand(for parameter: String?) -> URLCommand? {
        parameter.flatMap { $0.isEmpty ? nil : URLCommand(name: "automation", arguments: ["disable", $0]) }
    }
}

@objc(HolzBarEnableZenModeCommand)
nonisolated final class HolzBarEnableZenModeCommand: HolzBarScriptCommand {
    override func urlCommand(for parameter: String?) -> URLCommand? {
        URLCommand(name: "zen", arguments: ["on"])
    }
}

@objc(HolzBarDisableZenModeCommand)
nonisolated final class HolzBarDisableZenModeCommand: HolzBarScriptCommand {
    override func urlCommand(for parameter: String?) -> URLCommand? {
        URLCommand(name: "zen", arguments: ["off"])
    }
}

// MARK: - Properties of the application

/// What a script can read. Only names the user chose, and Booleans; no paths, no network names,
/// no app lists and nothing about scripts (T-13-L1).
extension NSApplication {
    @objc var holzBarProfileNames: [String] {
        AppState.current?.profiles.profiles.map(\.name) ?? []
    }

    @objc var holzBarCurrentProfile: String? {
        AppState.current?.profiles.currentProfileName
    }

    @objc var holzBarRuleNames: [String] {
        AppState.current?.automation.rules.map(\.name) ?? []
    }

    @objc var holzBarEnabledRuleNames: [String] {
        AppState.current?.automation.rules.filter(\.isEnabled).map(\.name) ?? []
    }

    @objc var holzBarZenMode: Bool {
        AppState.current?.menuBarManager.zenMode.isActive ?? false
    }

    @objc var holzBarHiddenSectionIsShown: Bool {
        AppState.current?.menuBarManager.section(withName: .hidden)?.isHidden == false
    }
}
