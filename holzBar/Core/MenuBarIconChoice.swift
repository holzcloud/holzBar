//
//  MenuBarIconChoice.swift
//  holzBar
//

import Foundation

/// The choice made on the cards of holzBar's menu bar icon: one of the styles, or no icon.
///
/// Two stored settings stand behind the cards: whether the icon is shown at all
/// (`ShowIceIcon`, kept under its old name) and which image set it uses (the stored
/// `ControlItemImageSet`). The cards show them as one choice, so "No icon" is a card of its own
/// and the style a user picked before stays stored while the icon is off.
nonisolated enum MenuBarIconChoice: Hashable {
    /// An icon of the style with this name (the raw name of `ControlItemImageSet.Name`).
    case style(String)
    /// No icon in the menu bar.
    case none

    /// The card that is selected for the stored settings.
    static func current(showsIcon: Bool, styleName: String) -> MenuBarIconChoice {
        showsIcon ? .style(styleName) : .none
    }

    /// Whether the icon is shown after this choice.
    var showsIcon: Bool {
        switch self {
        case .style: true
        case .none: false
        }
    }

    /// The style this choice stores, or `nil` for "No icon", which leaves the stored style as it is.
    var styleName: String? {
        switch self {
        case .style(let name): name
        case .none: nil
        }
    }
}

/// The ways to open holzBar's Settings.
///
/// With the icon in the menu bar a click on it (a right-click for its menu) is the way. Without
/// the icon one must remain, or a user who chose "No icon" could never change it back.
nonisolated enum SettingsAccess {
    /// A way to open Settings that does not need holzBar's icon.
    nonisolated enum Way: CaseIterable, Hashable {
        /// Opening holzBar again from Finder, Launchpad or Spotlight; macOS tells a running app
        /// it was reopened, and holzBar opens Settings.
        case reopenApp
        /// The `holzbar://settings` link.
        case link
        /// The Settings button of the search, which a hotkey opens.
        case searchPanel
        /// "Open Settings" in the command palette, which a hotkey opens.
        case commandPalette
    }

    /// The ways that are available now.
    ///
    /// - Parameters:
    ///   - hasSearchHotkey: Whether the hotkey of the search is set.
    ///   - hasCommandPaletteHotkey: Whether the hotkey of the command palette is set.
    /// - Returns: At least ``Way/reopenApp`` and ``Way/link``, which need nothing set.
    static func ways(hasSearchHotkey: Bool, hasCommandPaletteHotkey: Bool) -> [Way] {
        var ways: [Way] = [.reopenApp, .link]
        if hasSearchHotkey {
            ways.append(.searchPanel)
        }
        if hasCommandPaletteHotkey {
            ways.append(.commandPalette)
        }
        return ways
    }
}
