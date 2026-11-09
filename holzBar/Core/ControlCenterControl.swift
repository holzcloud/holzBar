//
//  ControlCenterControl.swift
//  holzBar
//

import Foundation

/// A Control Center control pinned to the menu bar on macOS 27 (Screenshot, Timer, Calculator,
/// Dark Mode, …).
///
/// macOS places these controls itself: a drag or a weight does not reach them, so holzBar shows
/// them as fixed. Their Accessibility identifier has the shape
/// `:<extension>:<container>:<control>`, with an empty first component and optionally a fifth
/// component, the UUID of the placed instance. macOS mints that UUID anew every time it places the
/// control, so it must not be part of the identity holzBar stores.
///
/// Adapted from Thaw's `ChronoControlIdentity` (GPL-3.0, see NOTICE).
nonisolated enum ControlCenterControl {
    /// The namespace of the process that hosts the system items on macOS 27.
    static let namespace = "com.apple.MenuBarAgent"

    /// Whether a title has the shape of a pinned control: an empty first component and three
    /// filled ones, optionally followed by an instance UUID.
    static func isPinnedControlTitle(_ title: String) -> Bool {
        let parts = title.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 4, 5:
            guard parts[0].isEmpty, parts[1...3].allSatisfy({ !$0.isEmpty }) else {
                return false
            }
            return parts.count == 4 || UUID(uuidString: String(parts[4])) != nil
        default:
            return false
        }
    }

    /// Whether an item is a pinned control. The namespace is part of the test, so an app cannot
    /// make its own item fixed by naming it like a control.
    static func isPinnedControl(namespace: String, title: String) -> Bool {
        namespace == Self.namespace && isPinnedControlTitle(title)
    }

    /// The title without the instance UUID of a pinned control; every other title is returned
    /// unchanged.
    static func stableIdentity(forTitle title: String) -> String {
        guard isPinnedControlTitle(title) else {
            return title
        }
        let parts = title.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 5 ? parts[..<4].joined(separator: ":") : title
    }
}
