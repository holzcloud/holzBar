//
//  HotkeyTarget.swift
//  holzBar
//

import Foundation

/// What a hotkey does: one of holzBar's actions, applying a layout profile or opening a
/// menu bar item's menu (THAW-15).
///
/// Every hotkey is stored in the `Hotkeys` setting under its ``storageKey``. An action
/// keeps its raw value, which was Ice's (see ``HotkeyAction``), so imported and synced
/// hotkeys keep working; profiles and items get keys with a prefix that no action uses.
nonisolated enum HotkeyTarget: Hashable, Sendable {
    /// One of holzBar's actions.
    case action(HotkeyAction)
    /// Applies the layout profile with this name.
    case applyProfile(String)
    /// Opens the menu of the item stored under this identity key.
    case openItem(String)

    /// The prefix of a profile's stored key.
    static let profilePrefix = "ApplyProfile:"

    /// The prefix of an item's stored key.
    static let itemPrefix = "OpenItem:"

    /// The key the hotkey is stored under.
    var storageKey: String {
        switch self {
        case .action(let action):
            action.rawValue
        case .applyProfile(let name):
            Self.profilePrefix + name
        case .openItem(let key):
            Self.itemPrefix + key
        }
    }

    /// Reads a stored key; `nil` for a key that names nothing holzBar knows.
    init?(storageKey: String) {
        if let action = HotkeyAction(rawValue: storageKey) {
            self = .action(action)
        } else if storageKey.hasPrefix(Self.profilePrefix) {
            let name = String(storageKey.dropFirst(Self.profilePrefix.count))
            guard !name.isEmpty else {
                return nil
            }
            self = .applyProfile(name)
        } else if storageKey.hasPrefix(Self.itemPrefix) {
            let key = String(storageKey.dropFirst(Self.itemPrefix.count))
            guard !key.isEmpty else {
                return nil
            }
            self = .openItem(key)
        } else {
            return nil
        }
    }

    /// Whether the target is a profile or an item, whose hotkeys come and go.
    var isDynamic: Bool {
        switch self {
        case .action:
            false
        case .applyProfile, .openItem:
            true
        }
    }

    /// A description for the log that names no profile and no item.
    var logDescription: String {
        switch self {
        case .action(let action):
            action.rawValue
        case .applyProfile:
            "a layout profile"
        case .openItem:
            "a menu bar item"
        }
    }
}
