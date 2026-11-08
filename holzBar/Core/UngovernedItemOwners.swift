//
//  UngovernedItemOwners.swift
//  holzBar
//

import Foundation

/// The processes whose menu bar items holzBar never moves by itself.
///
/// Before macOS 27 an item of a process without a bundle identifier is keyed by its process name.
/// Wine and CrossOver draw the tray icons of Windows apps from `explorer.exe`; they are placed by
/// the compatibility layer and holzBar must not move them. macOS 27's item provider never reads
/// processes without a bundle, so the rule matters below macOS 27 only.
///
/// Adapted from the `agentUngovernedOwners` list of Thaw's `MenuBarItemTag` (GPL-3.0, see NOTICE).
nonisolated enum UngovernedItemOwners {
    /// The process names, in lower case.
    static let processNames: Set<String> = ["explorer.exe"]

    /// Whether the namespace of an item names a process on the list; the case is ignored.
    static func contains(namespace: String) -> Bool {
        processNames.contains(namespace.lowercased())
    }
}
