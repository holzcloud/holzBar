//
//  MenuBarHitTesting.swift
//  holzBar
//

import Cocoa

// MARK: - Hit Testing

/// Where the mouse pointer is, relative to the menu bar, its items, the notch, the
/// holzBar Shelf and the holzBar icon. Show on click, hover and scroll and the smart
/// rehide decide with these. What depends on the macOS generation (whether a point is
/// on an item, or in the items' run of the bar) comes from the backend
/// (`MenuBarBackend`).
extension HIDEventManager {
    /// Returns the best screen to use for event manager calculations.
    /// Uses the screen under the mouse so menu bar hover/click work correctly
    /// with multiple displays (e.g. external monitor).
    func bestScreen(appState: AppState) -> NSScreen? {
        NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the menu bar.
    func isMouseInsideMenuBar(appState: AppState, screen: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationAppKit else {
            return false
        }

        // With "Displays have separate Spaces" off, only the primary display has
        // a menu bar. The top edge of any other display is ordinary space, and
        // treating it as a menu bar showed hidden items and holzBar's menu there
        // (jordanbaird/Ice#383, jordanbaird/Ice#456, jordanbaird/Ice#646).
        if !NSScreen.screensHaveSeparateSpaces, screen != NSScreen.screens.first {
            return false
        }

        // holzBar icon must be vertically visible. Otherwise, we can infer
        // that the menu bar is hidden and the mouse is not inside. Where the icon's
        // window says nothing about the menu bar (macOS 27), the visible frame check
        // below remains.
        if MenuBarBackends.current.iconWindowShowsMenuBar {
            guard
                let holzBarIcon = appState.menuBarManager.controlItem(withName: .visible),
                let holzBarIconFrame = holzBarIcon.frame,
                holzBarIconFrame.maxY <= screen.frame.maxY
            else {
                return false
            }
        }

        // Infer the menu bar frame from the screen frame.
        return mouseLocation.x >= screen.frame.minX &&
        mouseLocation.x <= screen.frame.maxX &&
        mouseLocation.y <= screen.frame.maxY &&
        mouseLocation.y >= screen.visibleFrame.maxY
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the current application menu.
    ///
    /// The frame comes from `ApplicationMenuFrames`, which reads it off the main thread:
    /// this runs for every click and mouse move, and asking an application that hangs
    /// would hold up every click on the Mac.
    func isMouseInsideApplicationMenu(appState: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationCoreGraphics,
            var applicationMenuFrame = appState.applicationMenuFrames.frame(for: screen)
        else {
            return false
        }
        applicationMenuFrame.size.width += applicationMenuFrame.origin.x - screen.frame.origin.x
        applicationMenuFrame.origin.x = screen.frame.origin.x
        return applicationMenuFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of a menu bar item.
    func isMouseInsideMenuBarItem(appState: AppState, screen: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        return MenuBarBackends.current.isInsideItem(point: mouseLocation, appState: appState)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the screen's notch, if it has one.
    ///
    /// If the screen does not have a notch, this property returns `false`.
    func isMouseInsideNotch(appState: AppState, screen: NSScreen) -> Bool {
        guard
            let mouseLocation = MouseHelpers.locationAppKit,
            var frameOfNotch = screen.frameOfNotch
        else {
            return false
        }
        frameOfNotch.size.height += 1
        return frameOfNotch.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of an empty space in the menu bar.
    func isMouseInsideEmptyMenuBarSpace(appState: AppState, screen: NSScreen) -> Bool {
        guard
            isMouseInsideMenuBar(appState: appState, screen: screen),
            !isMouseInsideApplicationMenu(appState: appState, screen: screen),
            !isMouseInsideMenuBarItem(appState: appState, screen: screen),
            !isMouseInsideNotch(appState: appState, screen: screen)
        else {
            return false
        }
        // Where the backend draws the items without windows (macOS 27), the gaps between
        // items are part of the items' own run of the bar.
        guard !isMouseInsideItemsArea(appState: appState, screen: screen) else {
            return false
        }
        // Last, as it reads the window list: a notch app's window above the bar is not
        // empty space (jordanbaird/Ice#933).
        return !isMouseInsideWindowAboveMenuBar(screen: screen)
    }

    /// A Boolean value that indicates whether another app's window stands above the menu
    /// bar at the mouse pointer, such as the controls of a notch app.
    ///
    /// Reads the window server's list (no Accessibility), at most every quarter second.
    func isMouseInsideWindowAboveMenuBar(screen: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        let now = ProcessInfo.processInfo.systemUptime
        let windows: [MenuBarOcclusion.Window]
        if let cached = windowsAboveMenuBar, now - cached.readAt < 0.25 {
            windows = cached.windows
        } else {
            windows = Self.readWindowsAboveMenuBar()
            windowsAboveMenuBar = (now, windows)
        }
        // A window as wide as the display is an overlay (dimming, screen annotation), not a
        // control standing over the bar.
        let displayWidth = CGDisplayBounds(screen.displayID).width
        return MenuBarOcclusion.isCovered(
            point: mouseLocation,
            windows: windows.filter { $0.bounds.width < displayWidth },
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    /// The windows on screen above the status bar's level.
    private static func readWindowsAboveMenuBar() -> [MenuBarOcclusion.Window] {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]]
        else {
            return []
        }
        return list.compactMap { info in
            guard
                let layer = info[kCGWindowLayer] as? Int,
                layer > MenuBarOcclusion.statusBarLayer,
                let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                let ownerPID = info[kCGWindowOwnerPID] as? pid_t
            else {
                return nil
            }
            let alpha = info[kCGWindowAlpha] as? Double ?? 1
            let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
                ?? (info[kCGWindowOwnerName] as? String == "Window Server" ? "com.apple.WindowServer" : nil)
            return (layer: layer, bounds: bounds, ownerPID: ownerPID, ownerBundleID: bundleID, alpha: alpha)
        }
    }

    /// A Boolean value that indicates whether the mouse pointer rests in the part of the
    /// menu bar that holds items, including the gaps between them.
    func isMouseInsideItemsArea(appState: AppState, screen: NSScreen) -> Bool {
        guard let mouseLocation = MouseHelpers.locationCoreGraphics else {
            return false
        }
        return MenuBarBackends.current.isInsideItemsArea(point: mouseLocation, screen: screen, appState: appState)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the holzBar Shelf panel.
    func isMouseInsideShelf(appState: AppState) -> Bool {
        guard let mouseLocation = MouseHelpers.locationAppKit else {
            return false
        }
        let panel = appState.menuBarManager.shelfPanel
        // Pad the frame to be more forgiving if the user accidentally
        // moves their mouse outside of the holzBar Shelf.
        let paddedFrame = panel.frame.insetBy(dx: -15, dy: -15)
        return paddedFrame.contains(mouseLocation)
    }

    /// A Boolean value that indicates whether the mouse pointer is within
    /// the bounds of the holzBar icon.
    func isMouseInsideHolzBarIcon(appState: AppState) -> Bool {
        guard
            let visibleSection = appState.menuBarManager.section(withName: .visible),
            let holzBarIconFrame = visibleSection.controlItem.frame,
            let mouseLocation = MouseHelpers.locationAppKit
        else {
            return false
        }
        return holzBarIconFrame.contains(mouseLocation)
    }
}
