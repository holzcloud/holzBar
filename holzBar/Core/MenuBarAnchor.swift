//
//  MenuBarAnchor.swift
//  holzBar
//

import Foundation

// On macOS the geometry members of CGRect and CGPoint live in CoreGraphics, which the app's
// member import visibility requires; on Linux Foundation provides them.
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Whether the menu bar of the display under the pointer is shown, before macOS 27, for show on
/// click, hover and scroll.
///
/// Before macOS 27 holzBar's item windows move up with the bar: a window whose top edge is above
/// the display means the bar is hidden there (a fullscreen Space, the bar hidden by the system).
/// That used to be asked of the holzBar icon only, which fails in two cases (pre27-M7, D-11):
/// the icon can be off from launch on, and then its window frame is never known, so the gestures
/// never worked; and on a second display with separate Spaces the icon's frame says nothing about
/// that display's bar, whose top edge can be lower. So the icon decides only on its own display,
/// then the hidden section's divider (always in the bar), and a display with neither falls back to
/// what the system says. While the icon's frame is valid on that display the result is the one of
/// before.
nonisolated enum MenuBarAnchor {
    /// What the decision was taken from.
    enum Kind: String, Equatable, Sendable {
        /// The holzBar icon's window.
        case icon
        /// The hidden section's divider's window.
        case divider
        /// Neither is on the display; the system's state decides.
        case none
    }

    /// Whether the bar is shown on the display with the given frame, and what said so.
    ///
    /// All frames are in AppKit coordinates. An item is on the display when the point 1 pt inside
    /// its right edge lies within the display's horizontal extent: the hidden divider stretches
    /// 10,000 pt to the left while its section is hidden, and only its right end stands in the bar.
    ///
    /// - Parameters:
    ///   - iconFrame: The holzBar icon's window frame, `nil` when it is not known.
    ///   - dividerFrame: The hidden section's divider's window frame, `nil` when it is not known.
    ///   - screenFrame: The frame of the display under the pointer.
    ///   - systemHidesBar: Whether the system hides the menu bar; asked only without an anchor.
    ///   - isFullscreen: Whether that display shows a fullscreen Space; asked only without an
    ///     anchor.
    static func evaluate(
        iconFrame: CGRect?,
        dividerFrame: CGRect?,
        screenFrame: CGRect,
        systemHidesBar: @autoclosure () -> Bool,
        isFullscreen: @autoclosure () -> Bool
    ) -> (anchor: Kind, barIsShown: Bool) {
        if let iconFrame, isOnDisplay(iconFrame, screenFrame) {
            return (.icon, iconFrame.maxY <= screenFrame.maxY)
        }
        if let dividerFrame, isOnDisplay(dividerFrame, screenFrame) {
            return (.divider, dividerFrame.maxY <= screenFrame.maxY)
        }
        return (.none, !systemHidesBar() && !isFullscreen())
    }

    /// Whether the item with the given frame stands on the display with the given frame.
    private static func isOnDisplay(_ frame: CGRect, _ screenFrame: CGRect) -> Bool {
        let x = frame.maxX - min(1, frame.width / 2)
        return x >= screenFrame.minX && x < screenFrame.maxX
    }
}
