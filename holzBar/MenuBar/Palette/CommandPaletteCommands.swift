//
//  CommandPaletteCommands.swift
//  holzBar
//

import SwiftUI

/// Builds the palette's commands from the app's state and runs them through the services
/// that hotkeys, URL commands and Shortcuts use. Nothing here creates or edits a rule, a
/// script or a setting; a rule that uses a script is never turned on from the palette.
@MainActor
enum CommandPaletteCommands {
    /// The actions in the catalog's fixed order.
    private static let actions: [HotkeyAction] = [
        .toggleZenMode,
        .toggleHiddenSection,
        .toggleAlwaysHiddenSection,
        .showHiddenSectionTemporarily,
        .toggleKeepAwake,
        .toggleAutoRehide,
        .enableShelf,
        .toggleApplicationMenus,
        .searchMenuBarItems,
        .showItemHints,
    ]

    static func make(appState: AppState) -> [PaletteCommand] {
        var commands = actions.map { PaletteCommand(kind: .action($0), title: $0.title, keywords: keywords(for: $0)) }
        if appState.automation.isKeepAwakeOn, let index = commands.firstIndex(where: { $0.kind == .action(.toggleKeepAwake) }) {
            commands[index] = PaletteCommand(
                kind: .action(.toggleKeepAwake),
                title: String(localized: "Let the Mac sleep again"),
                keywords: keywords(for: .toggleKeepAwake)
            )
        }
        commands.append(PaletteCommand(kind: .openSettings, title: String(localized: "Open Settings"), keywords: [String(localized: "Preferences")]))
        for profile in appState.profiles.profiles {
            commands.append(PaletteCommand(
                kind: .applyProfile(profile.name),
                title: String(localized: "Apply profile \(URLPrompt.displayName(profile.name))")
            ))
        }
        for mood in appState.appearanceManager.moods {
            commands.append(PaletteCommand(
                kind: .applyMood(mood.name),
                title: String(localized: "Apply mood \(mood.name)"),
                keywords: [String(localized: "look"), String(localized: "appearance")]
            ))
        }
        for rule in appState.automation.rules {
            let name = URLPrompt.displayName(rule.name)
            if rule.isEnabled {
                commands.append(PaletteCommand(kind: .setRule(rule.id, isEnabled: false), title: String(localized: "Turn off rule \(name)")))
            } else if !rule.usesScript {
                commands.append(PaletteCommand(kind: .setRule(rule.id, isEnabled: true), title: String(localized: "Turn on rule \(name)")))
            }
        }
        let itemManager = appState.itemManager
        for section in MenuBarSection.Name.allCases {
            for item in itemManager.itemCache[section] where !item.isControlItem {
                commands.append(PaletteCommand(
                    kind: .openItem(itemManager.identityKey(for: item)),
                    title: item.displayName
                ))
            }
        }
        return commands
    }

    static func perform(_ command: PaletteCommand, appState: AppState) {
        switch command.kind {
        case .action(let action):
            action.perform(appState: appState)
        case .applyProfile(let name):
            appState.profiles.apply(named: name)
        case .applyMood(let name):
            appState.appearanceManager.applyMood(named: name)
        case .setRule(let id, let isEnabled):
            appState.automation.setRule(withID: id, enabled: isEnabled)
        case .openItem(let key):
            appState.itemManager.openItem(withIdentityKey: key)
        case .openSettings:
            appState.activate(for: .settings)
            appState.openWindow(.settings)
        }
    }

    static func symbol(for command: PaletteCommand) -> String {
        switch command.kind {
        case .action(.toggleZenMode): "moon"
        case .action(.toggleKeepAwake): "cup.and.saucer"
        case .action(.searchMenuBarItems): "magnifyingglass"
        case .action: "slider.horizontal.3"
        case .applyProfile: "rectangle.3.group"
        case .applyMood: "paintpalette"
        case .setRule: "wand.and.stars"
        case .openItem: "menubar.rectangle"
        case .openSettings: "gearshape"
        }
    }

    static func kindLabel(for command: PaletteCommand) -> Text {
        switch command.kind {
        case .action, .openSettings: Text("Action")
        case .applyProfile: Text("Profile")
        case .applyMood: Text("Mood")
        case .setRule: Text("Rule")
        case .openItem: Text("Menu Bar Item")
        }
    }

    private static func keywords(for action: HotkeyAction) -> [String] {
        switch action {
        case .toggleZenMode: [String(localized: "quiet"), String(localized: "focus")]
        case .toggleKeepAwake: [String(localized: "sleep"), String(localized: "caffeinate")]
        case .toggleHiddenSection, .toggleAlwaysHiddenSection, .showHiddenSectionTemporarily: [String(localized: "reveal")]
        default: []
        }
    }
}
