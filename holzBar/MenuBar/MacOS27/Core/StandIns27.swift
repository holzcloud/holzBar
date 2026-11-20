//
//  StandIns27.swift
//  holzBar
//

import Foundation

/// Decides which stand-in icons holzBar draws on macOS 27, and names their status items.
///
/// MenuBarAgent hides the items of an application it cannot name (``UnnameableApps27``)
/// whenever any assertion, holzBar's included, conceals something, even when the user placed
/// the application in Visible. holzBar then draws an item of its own in its place: a
/// stand-in, which shows the application's picture or icon and opens the real item on a
/// click. Everything here is pure; the status items are ``StandInItems27``'s.
nonisolated enum StandIns27 {
    /// What to draw.
    nonisolated struct Plan: Equatable, Sendable {
        /// The applications with a stand-in, in the order of the bar and without duplicates.
        /// While a hold lasts they stay in the plan, so a stand-in keeps its place.
        var bundleIDs: [String]
        /// Whether the stand-ins are drawn: only while something is concealed and no
        /// release-all hold draws the real items.
        var isShown: Bool
    }

    /// No stand-ins at all.
    static let none = Plan(bundleIDs: [], isShown: false)

    /// The stand-ins for the visible applications MenuBarAgent cannot name.
    ///
    /// - Parameters:
    ///   - isEnabled: The stand-in switch.
    ///   - holzBarIsNameable: Whether holzBar itself runs from a place MenuBarAgent names. If
    ///     it does not, the bar conceals holzBar's own items too, stand-ins included.
    ///   - unnameableVisible: The bundle identifiers of those applications, in bar order.
    ///   - isConcealing: Whether anything is concealed (counting suspensions).
    ///   - isHoldingRelease: Whether a release-all hold draws every item.
    static func plan(
        isEnabled: Bool,
        holzBarIsNameable: Bool,
        unnameableVisible: [String],
        isConcealing: Bool,
        isHoldingRelease: Bool
    ) -> Plan {
        guard isEnabled, holzBarIsNameable, isConcealing || isHoldingRelease else {
            return none
        }
        var seen = Set<String>()
        let bundleIDs = unnameableVisible.filter { seen.insert($0).inserted }
        return Plan(bundleIDs: bundleIDs, isShown: isConcealing && !isHoldingRelease)
    }

    /// The start of every stand-in's autosave name. It differs from the `holzBar.Widget.`
    /// prefix of a widget and from every control item's title: the macOS 27 provider
    /// (`tag(for:ownPID:)`) drops an own item that is neither, so a stand-in never reaches
    /// the item cache, the layout, the holzBar Shelf, the image store or ``HiddenAnyway27``.
    static let autosaveNamePrefix = "holzBar.StandIn."

    /// The autosave name of the stand-in for an application.
    ///
    /// macOS stores the name in holzBar's preferences, under the keys of the item's position.
    /// The name is a 64-bit FNV-1a hash of the bundle identifier, so those preferences never
    /// hold which applications the user runs in clear. The same application always gets the
    /// same name, so its stand-in returns to the place the user dragged it to.
    static func autosaveName(for bundleID: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bundleID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let digits = String(hash, radix: 16)
        return autosaveNamePrefix + String(repeating: "0", count: 16 - digits.count) + digits
    }
}
