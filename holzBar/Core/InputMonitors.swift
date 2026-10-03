//
//  InputMonitors.swift
//  holzBar
//

import Foundation

/// Which input monitors the current settings need.
///
/// Every monitor wakes holzBar for each event of its kind anywhere in the system,
/// so `HIDEventManager` runs only the ones a setting needs. The mouse-moved tap in
/// particular woke holzBar on every mouse move, even with "Show on hover" off.
nonisolated enum InputMonitors {
    /// A kind of input event holzBar can monitor.
    nonisolated enum Kind: Hashable, CaseIterable {
        /// Left and right mouse-down: show on click, smart rehide, the secondary
        /// context menu, and the click that pauses show on hover.
        case mouseDown
        /// Left mouse-up: ends a Command-drag of a menu bar item, which also records the
        /// sections the user arranged.
        case mouseUp
        /// Left mouse-dragged: starts a Command-drag of a menu bar item.
        case mouseDragged
        /// Mouse moves (an HID event tap): show on hover.
        case mouseMoved
        /// Scroll wheel: show on scroll.
        case scrollWheel
    }

    /// The settings that decide which monitors run.
    nonisolated struct Settings: Equatable {
        var showOnClick = false
        var showOnHover = false
        var showOnScroll = false
        var autoRehide = false
        /// Whether rehiding uses the smart strategy (a click outside the shown items).
        var rehidesSmartly = false
        var secondaryContextMenu = false
        /// Whether the holzBar Shelf is used, which lets clicks keep show on hover going.
        var usesShelf = false
        var showAllSectionsOnUserDrag = false
        /// Whether holzBar saves and restores the section of each item (before macOS 27),
        /// so the end of a Command-drag on the bar must be noticed.
        var savesUserArrangement = false
        /// Whether a custom menu bar appearance draws overlay panels, which fade while
        /// an item is dragged.
        var hasCustomAppearance = false
    }

    /// The monitors the given settings need.
    static func needed(for settings: Settings) -> Set<Kind> {
        var kinds = Set<Kind>()
        if settings.showOnHover {
            kinds.insert(.mouseMoved)
        }
        if settings.showOnScroll {
            kinds.insert(.scrollWheel)
        }
        let rehidesOnClick = settings.autoRehide && settings.rehidesSmartly
        // Without the Shelf, a click in the menu bar pauses show on hover.
        let hoverPausesOnClick = settings.showOnHover && !settings.usesShelf
        if settings.showOnClick || rehidesOnClick || settings.secondaryContextMenu || hoverPausesOnClick {
            kinds.insert(.mouseDown)
        }
        if settings.showAllSectionsOnUserDrag || settings.hasCustomAppearance {
            kinds.insert(.mouseUp)
            kinds.insert(.mouseDragged)
        }
        // Only the mouse-up, one event per click: a Command-drag on the bar ends with it.
        if settings.savesUserArrangement {
            kinds.insert(.mouseUp)
        }
        return kinds
    }

    /// Whether the universal click monitor that refreshes the active space is needed.
    ///
    /// A click can change the active space without a notification only when it moves
    /// focus between displays or into or out of a fullscreen space; with one display
    /// and no fullscreen space the space notifications are enough.
    static func needsSpaceClickMonitor(isFullscreenSpace: Bool, screenCount: Int) -> Bool {
        isFullscreenSpace || screenCount > 1
    }
}
