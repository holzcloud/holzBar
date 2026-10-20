//
//  ActionCatalog.swift
//  holzBar
//

import Foundation

/// One thing the command palette can run: a holzBar action, a profile, a rule, a menu bar
/// item or the Settings window.
///
/// The catalog is a thin list over services that already exist. A command carries what the
/// matching hotkey, URL command or Shortcuts action carries, never a new code path, and
/// nothing about what the user ran is kept.
nonisolated struct PaletteCommand: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        /// One of holzBar's hotkey actions.
        case action(HotkeyAction)
        /// Applies the layout profile with this name.
        case applyProfile(String)
        /// Turns an automation rule on or off.
        case setRule(UUID, isEnabled: Bool)
        /// Opens the menu of the item with this identity key.
        case openItem(String)
        /// Opens the Settings window.
        case openSettings
    }

    let kind: Kind
    /// The localized name that is shown and searched.
    let title: String
    /// Extra words that find the command, localized by the caller.
    var keywords: [String] = []

    var id: String {
        switch kind {
        case .action(let action):
            "action:\(action.rawValue)"
        case .applyProfile(let name):
            "profile:\(name)"
        case .setRule(let ruleID, let isEnabled):
            "rule:\(ruleID.uuidString):\(isEnabled)"
        case .openItem(let key):
            "item:\(key)"
        case .openSettings:
            "settings"
        }
    }

    /// Whether the command is an action rather than a menu bar item.
    var isAction: Bool {
        if case .openItem = kind {
            return false
        }
        return true
    }

    /// The text the palette searches: the title, then the keywords.
    var searchText: String {
        ([title] + keywords).joined(separator: " ")
    }
}

nonisolated enum ActionCatalog {
    /// The prefix that limits the palette to actions.
    static let actionsOnlyPrefix: Character = ">"

    /// The commands that match what the user typed, best first.
    ///
    /// An empty query returns the commands in the order given, which is the catalog's fixed
    /// order. A query that starts with ``actionsOnlyPrefix`` leaves out the menu bar items.
    /// Equal scores keep their order, so the result is the same every time.
    static func results(for query: String, in commands: [PaletteCommand]) -> [PaletteCommand] {
        var text = query.drop { $0.isWhitespace }
        var candidates = commands
        if text.first == actionsOnlyPrefix {
            text = text.dropFirst()
            candidates = commands.filter(\.isAction)
        }
        return FuzzyMatch.rank(candidates, query: String(text)) { $0.searchText }
    }
}
