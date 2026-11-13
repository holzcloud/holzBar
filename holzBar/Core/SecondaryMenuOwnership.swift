//
//  SecondaryMenuOwnership.swift
//  holzBar
//

import Foundation

/// Who a right-click on empty menu bar space belongs to: holzBar's menu or Apple's.
///
/// From macOS 27.2 MenuBarAgent opens Apple's own menu about 60 ms after a right-click on
/// empty menu bar space, so holzBar's menu, which opens 100 ms after the click, would fight
/// it. There a plain right-click stays Apple's, and holzBar's menu opens only with ⌥ Option
/// held. Before macOS 27.2 a right-click opens holzBar's menu as it always did.
nonisolated enum SecondaryMenuOwnership {
    /// Whether macOS opens its own menu for a right-click on empty menu bar space.
    static func systemOpensOwnMenu(major: Int, minor: Int) -> Bool {
        major > 27 || (major == 27 && minor >= 2)
    }

    /// Whether a right-click on empty menu bar space opens holzBar's menu.
    ///
    /// - Parameters:
    ///   - optionHeld: Whether ⌥ Option was held with the click.
    ///   - major: The major version of macOS.
    ///   - minor: The minor version of macOS.
    static func opensHolzBarMenu(optionHeld: Bool, major: Int, minor: Int) -> Bool {
        optionHeld || !systemOpensOwnMenu(major: major, minor: minor)
    }

    /// Whether macOS opens its own menu for a right-click on empty menu bar space on this Mac.
    static var systemOpensOwnMenu: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return systemOpensOwnMenu(major: version.majorVersion, minor: version.minorVersion)
    }

    /// Whether a right-click on empty menu bar space opens holzBar's menu on this Mac.
    static func opensHolzBarMenu(optionHeld: Bool) -> Bool {
        optionHeld || !systemOpensOwnMenu
    }
}
