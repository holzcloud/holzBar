//
//  ClockClickPolicy.swift
//  holzBar
//

import Foundation

/// Decides which clicks on a system item the macOS 27 click bridge takes over.
///
/// While items are hidden, MenuBarAgent ignores a click on the clock (measured on macOS 27.0), so
/// holzBar holds the click back, lifts the concealment for a moment and replays it; Notification
/// Center then opens. The user can turn that off for the clock: its click then reaches
/// MenuBarAgent unchanged, and does nothing while items are hidden. The other system items stay
/// bridged.
nonisolated enum ClockClickPolicy {
    /// The identifier of the clock's item.
    static let clockIdentifier = "com.apple.menuextra.clock"

    /// Whether the identifier is the clock's.
    static func isClock(_ identifier: String?) -> Bool {
        identifier == clockIdentifier
    }

    /// Whether the bridge takes over a click on the given system item.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the clicked system item, or `nil` for an item that is
    ///     not known (the overflow button), which is always bridged.
    ///   - clockOpensNotificationCenter: The setting.
    static func bridges(item identifier: String?, clockOpensNotificationCenter: Bool) -> Bool {
        !isClock(identifier) || clockOpensNotificationCenter
    }
}
