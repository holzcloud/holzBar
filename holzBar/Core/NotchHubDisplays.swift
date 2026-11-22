//
//  NotchHubDisplays.swift
//  holzBar
//

import Foundation

/// The displays the Notch hub may open on.
///
/// The raw values are stored in the settings; new cases go at the end.
nonisolated enum NotchHubDisplays: Int, CaseIterable, Sendable {
    /// Every display: at the notch where there is one, hanging from the top centre elsewhere.
    case all = 0

    /// The built-in display only.
    case builtIn = 1

    /// Displays with a camera cutout only: a notch, or Apple's Dynamic Island (decision D-17 of
    /// Phase 93). Callers pass `safeAreaInsets.top != 0` as `hasNotch`, which is true for both.
    case notched = 2

    /// Whether the hub may open on a display.
    ///
    /// - Parameters:
    ///   - isBuiltIn: Whether the display is the Mac's built-in one.
    ///   - hasNotch: Whether the display has any camera cutout, Apple's Dynamic Island included.
    func includes(isBuiltIn: Bool, hasNotch: Bool) -> Bool {
        switch self {
        case .all: true
        case .builtIn: isBuiltIn
        case .notched: hasNotch
        }
    }
}
