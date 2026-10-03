//
//  InterfaceWindowRule.swift
//  holzBar
//

import Foundation

/// Which windows count as the open menu of an item that holzBar showed for a moment.
///
/// holzBar waits to hide such an item again while its menu is open. Any new window of the
/// item's app used to count, so a small floating window of another kind — a Dock preview,
/// a picture-in-picture window, a HUD — kept holzBar waiting, and the item never went back
/// (Thaw #1158). Only windows at the levels of menus count now.
nonisolated enum InterfaceWindowRule {
    /// The window levels of menus: the main menu (24), the status bar (25), and pop-up
    /// menus (101, and 100 just below it).
    static let menuLayers: Set<Int> = [24, 25, 100, 101]

    /// Whether a window counts as the item's open menu: a window of the item's app that
    /// appeared after the click, at the level of a menu.
    static func counts(layer: Int, isOwnersWindow: Bool, appearedAfterClick: Bool) -> Bool {
        isOwnersWindow && appearedAfterClick && menuLayers.contains(layer)
    }
}
