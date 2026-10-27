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

    /// Displays with a notch only.
    case notched = 2

    /// Whether the hub may open on a display.
    func includes(isBuiltIn: Bool, hasNotch: Bool) -> Bool {
        switch self {
        case .all: true
        case .builtIn: isBuiltIn
        case .notched: hasNotch
        }
    }
}
