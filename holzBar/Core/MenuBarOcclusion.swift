//
//  MenuBarOcclusion.swift
//  holzBar
//

import CoreGraphics
import Foundation

/// Whether another app's window stands above the menu bar at a point.
///
/// Notch apps (boring.notch, NotchNook and others) draw their controls in windows above
/// the menu bar, at the level of the main menu plus a few. A click on such a control is
/// a click on that app, not on empty menu bar space, so show on click must not toggle
/// the hidden items (jordanbaird/Ice#933).
nonisolated enum MenuBarOcclusion {
    /// A window on screen, as the window server lists it.
    typealias Window = (layer: Int, bounds: CGRect, ownerPID: pid_t, ownerBundleID: String?, alpha: Double)

    /// The level of the status bar (25); a window above it stands over the menu bar.
    static let statusBarLayer = 25

    /// The system's own processes, whose windows above the bar belong to the bar itself.
    static let systemOwners: Set<String> = [
        "com.apple.WindowServer",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.MenuBarAgent",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
    ]

    /// Whether a window of another, non-system app above the status bar level, visible and
    /// containing the point, covers the menu bar there.
    ///
    /// - Parameters:
    ///   - point: The point, in the window server's coordinates.
    ///   - windows: The windows on screen.
    ///   - ownPID: holzBar's process identifier.
    ///   - systemOwners: The bundle identifiers of the system's own processes.
    static func isCovered(point: CGPoint, windows: [Window], ownPID: pid_t, systemOwners: Set<String> = MenuBarOcclusion.systemOwners) -> Bool {
        windows.contains { window in
            window.layer > statusBarLayer &&
            window.alpha > 0 &&
            window.ownerPID != ownPID &&
            !(window.ownerBundleID.map(systemOwners.contains) ?? false) &&
            window.bounds.contains(point)
        }
    }
}
