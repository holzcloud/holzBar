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

    /// The level of pop-up menus (101) and the one just below it (100).
    private static let popUpMenuLayers: Set<Int> = [100, 101]

    /// The level of the status bar (25).
    private static let statusBarLayer = 25

    /// How much taller than the menu bar a status-bar window must be to count as a menu,
    /// so that rounding never makes an item's own window count.
    private static let statusBarSlack: CGFloat = 2

    /// The smaller side, in points, under which a window is too thin to be a menu.
    ///
    /// A KVM or screen-edge helper puts a window of one point at the edge of a display (a hot
    /// border; Hidden Bar #548), and such a window kept the sections open for good. No menu,
    /// popover or panel is that thin, so such a window never counts. The limit is holzBar's
    /// choice within D-12 of phase 93, a little above the 1-point borders seen.
    static let thinWindowLimit: CGFloat = 8

    /// Whether a window is the open menu of an item in a shown hidden section, so that no
    /// rehide pulls the item away under it.
    ///
    /// The window must belong to one of `shownOwners`, the apps of the items in the hidden
    /// and always-hidden sections, and must not be thin (see ``thinWindowLimit``). A pop-up
    /// menu (layer 100 or 101) counts at any height. At the status-bar level (25) only a
    /// window taller than the tallest menu bar counts (a popover or a panel): every status
    /// item's own window sits at that level in the bar, so without the height test nothing
    /// would ever hide again. Application menus (24) and ordinary windows never count, so an
    /// app cannot keep the section open with one.
    ///
    /// A window may start above the bar's lower edge: macOS 27 popups reach into the bar. So
    /// the rule takes no frame origin and sets no minimum-y bound (Hidden Bar #548).
    static func isOpenMenu(
        layer: Int,
        width: CGFloat,
        height: CGFloat,
        ownerPID: Int32,
        shownOwners: Set<Int32>,
        barHeight: CGFloat
    ) -> Bool {
        guard shownOwners.contains(ownerPID), min(width, height) >= thinWindowLimit else {
            return false
        }
        if popUpMenuLayers.contains(layer) {
            return true
        }
        return layer == statusBarLayer && height > barHeight + statusBarSlack
    }
}
