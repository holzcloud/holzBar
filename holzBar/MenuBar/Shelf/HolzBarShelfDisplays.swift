//
//  HolzBarShelfDisplays.swift
//  holzBar
//

import SwiftUI

/// The displays the holzBar Shelf is used on.
///
/// On the other displays, hidden items are shown in the menu bar itself
/// (jordanbaird/Ice#223, jordanbaird/Ice#188, jordanbaird/Ice#703,
/// jordanbaird/Ice#797, jordanbaird/Ice#303).
enum HolzBarShelfDisplays: Int, CaseIterable, Identifiable {
    /// The holzBar Shelf is used on every display.
    case all = 0

    /// The holzBar Shelf is used on the built-in display only.
    case builtIn = 1

    /// The holzBar Shelf is used on displays with a notch only.
    case notched = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .all: "All displays"
        case .builtIn: "Built-in display only"
        case .notched: "Displays with a notch only"
        }
    }

    /// The text of the choice, for places that show it as a plain string (the sync sheet).
    var title: String {
        switch self {
        case .all: String(localized: "All displays")
        case .builtIn: String(localized: "Built-in display only")
        case .notched: String(localized: "Displays with a notch only")
        }
    }

    /// Returns a Boolean value that indicates whether the holzBar Shelf is used on
    /// the given screen.
    func includes(_ screen: NSScreen?) -> Bool {
        switch self {
        case .all:
            return true
        case .builtIn:
            guard let screen else {
                return false
            }
            return CGDisplayIsBuiltin(screen.displayID) != 0
        case .notched:
            return screen?.hasNotch ?? false
        }
    }
}
