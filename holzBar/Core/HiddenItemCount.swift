//
//  HiddenItemCount.swift
//  holzBar
//

import Foundation

/// Decides what the count badge on holzBar's icon says: how many items are hidden right now.
///
/// The rule beside ``CaptureIndicator``. The caller passes the item counts of the sections
/// without control items; this only decides whether there is a badge and what it reads.
nonisolated enum HiddenItemCount {
    /// The largest number the badge writes out; a larger count reads "99+".
    static let maximumShown = 99

    /// The number on the badge and the text it shows.
    struct Badge: Equatable, Sendable {
        /// The number of hidden items, never below 1.
        let count: Int
        /// The text drawn on the badge: "1" to "99", or "99+".
        let text: String
    }

    /// The badge for the given counts, or `nil` for none.
    ///
    /// - Parameters:
    ///   - hidden: The number of items in the hidden section, without control items.
    ///   - alwaysHidden: The number of items in the always-hidden section, without control items.
    ///   - includesAlwaysHidden: Whether the always-hidden section counts as well.
    ///   - isHiding: Whether the items are hidden now (not shown, and the Shelf is closed).
    ///   - isEnabled: Whether the user switched the badge on.
    static func badge(hidden: Int, alwaysHidden: Int, includesAlwaysHidden: Bool, isHiding: Bool, isEnabled: Bool) -> Badge? {
        guard isEnabled, isHiding else {
            return nil
        }
        // A negative count is a bug upstream; it counts as nothing rather than cancelling another.
        let first = max(hidden, 0)
        let second = includesAlwaysHidden ? max(alwaysHidden, 0) : 0
        let (sum, overflow) = first.addingReportingOverflow(second)
        let count = overflow ? Int.max : sum
        guard count > 0 else {
            return nil
        }
        let text = count > maximumShown ? "\(maximumShown)+" : String(count)
        return Badge(count: count, text: text)
    }
}
