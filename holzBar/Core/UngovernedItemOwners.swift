//
//  UngovernedItemOwners.swift
//  holzBar
//

import Foundation

/// The processes whose menu bar items holzBar never moves by itself.
///
/// Before macOS 27 an item of a process without a bundle identifier is keyed by its process name.
/// Wine and CrossOver draw the tray icons of Windows apps from `explorer.exe`; they are placed by
/// the compatibility layer, so no restore, new-item placement, order pass or repair moves them.
/// The user still can: a drag, the Layout pane, a profile the user saved, and opening the item
/// from the Shelf, search or a group all move it as any other item. macOS 27's item provider
/// never reads processes without a bundle, so the rule matters below macOS 27 only.
///
/// Adapted from the `agentUngovernedOwners` list of Thaw's `MenuBarItemTag` (GPL-3.0, see NOTICE).
nonisolated enum UngovernedItemOwners {
    /// The process names, in lower case.
    static let processNames: Set<String> = ["explorer.exe"]

    /// Whether the namespace of an item names a process on the list; the case is ignored.
    static func contains(namespace: String) -> Bool {
        processNames.contains(namespace.lowercased())
    }

    /// Whether a pass that reconciles the sections may move an item: always for the user's own
    /// arrangement (a profile, the Layout pane), and for an automatic pass (restore, new items,
    /// order, repair) only when the item's process is not on the list.
    ///
    /// - Parameters:
    ///   - isUngoverned: Whether the item belongs to a process on the list (below macOS 27).
    ///   - arrangedByUser: Whether the pass applies an arrangement the user made.
    static func allowsReconciling(isUngoverned: Bool, arrangedByUser: Bool) -> Bool {
        arrangedByUser || !isUngoverned
    }
}
