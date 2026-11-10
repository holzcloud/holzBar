//
//  ControlItemOrder.swift
//  holzBar
//

import Foundation

// On macOS the geometry members of CGRect and CGPoint live in CoreGraphics, which the app's
// member import visibility requires; on Linux Foundation provides them.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The order holzBar keeps among its own items before macOS 27: the holzBar icon right of the
/// hidden section's divider, and the always-hidden section's divider left of it.
///
/// The user can ⌘-drag holzBar's icon into the hidden section like any other item. There it is
/// pushed off screen with the section at the next hide, and the way back to holzBar's menu is gone
/// (pre27-M6). `NSStatusItem` offers no public way to refuse that drag, and an event tap that
/// watched every drag would cost something while nothing happens, so holzBar reverts the result
/// instead: the next read of the bar that finds the icon left of the divider moves it back
/// (D-10, D-15).
nonisolated enum ControlItemOrder {
    /// A move that puts one of holzBar's items back in its place.
    enum Correction: Equatable, Sendable {
        /// The holzBar icon goes back right of the hidden section's divider.
        case iconRightOfHidden
        /// The always-hidden section's divider goes back left of the hidden section's divider.
        case alwaysHiddenLeftOfHidden
    }

    /// The moves that restore the order, the icon first.
    ///
    /// - Parameters:
    ///   - icon: The holzBar icon's frame, or `nil` when the icon is not in the bar.
    ///   - hidden: The hidden section's divider's frame.
    ///   - alwaysHidden: The always-hidden section's divider's frame, or `nil` when that
    ///     section is off.
    static func corrections(icon: CGRect?, hidden: CGRect, alwaysHidden: CGRect?) -> [Correction] {
        var corrections: [Correction] = []
        if let icon, icon.maxX <= hidden.minX {
            corrections.append(.iconRightOfHidden)
        }
        if let alwaysHidden, hidden.maxX <= alwaysHidden.minX {
            corrections.append(.alwaysHiddenLeftOfHidden)
        }
        return corrections
    }
}
