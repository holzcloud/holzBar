//
//  ItemOpenOrigin.swift
//  holzBar
//

/// How an open of a menu bar item was started.
///
/// Every surface that opens an item goes through one place (`ItemOpener`). A widget answers the
/// open with its own action, and a script widget then asks its script again. Only the user's
/// own click skips the spacing between two asks; anything that can fire again and again without
/// a click (a Shortcut in a repeat, a held hotkey, a hint, a group) keeps it (WR-02).
nonisolated enum ItemOpenOrigin: Equatable, Sendable {
    /// The user's own click or pick on the item: in the holzBar Shelf or in the search.
    case click
    /// An item hotkey, a hint, a group or the Shortcuts action: opened without a click on the
    /// item.
    case command

    /// Whether the open is the user's own click on the item.
    var isUserClick: Bool {
        self == .click
    }
}
