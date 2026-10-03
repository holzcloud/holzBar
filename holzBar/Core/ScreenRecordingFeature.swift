//
//  ScreenRecordingFeature.swift
//  holzBar
//

import Foundation

/// A feature of holzBar that needs the Screen Recording permission.
///
/// holzBar asks for Screen Recording only the first time one of these features is used,
/// and the request names the feature and why it needs the permission. Everything else
/// works with Accessibility alone.
nonisolated enum ScreenRecordingFeature: CaseIterable, Sendable {
    /// The holzBar Shelf, which shows the hidden items below the menu bar.
    case shelf

    /// The search for menu bar items.
    case search

    /// The Menu Bar Layout pane of the settings.
    case layoutPane

    /// A menu bar shape, chosen in the menu bar appearance.
    case menuBarShape

    /// The feature's name, as it appears in holzBar.
    var name: String {
        switch self {
        case .shelf:
            "holzBar Shelf"
        case .search:
            "search"
        case .layoutPane:
            "Menu Bar Layout pane"
        case .menuBarShape:
            "menu bar shape"
        }
    }

    /// One sentence that says why the feature needs Screen Recording.
    var reason: String {
        switch self {
        case .shelf:
            "The holzBar Shelf shows pictures of your menu bar items, which macOS lets an app take only with Screen Recording."
        case .search:
            "The search shows pictures of your menu bar items, which macOS lets an app take only with Screen Recording. You can search by name without it."
        case .layoutPane:
            "The Menu Bar Layout pane shows pictures of your menu bar items, which macOS lets an app take only with Screen Recording."
        case .menuBarShape:
            "A menu bar shape draws the wallpaper beside the shape, which macOS lets an app read only with Screen Recording."
        }
    }

    /// What Screen Recording is for, in one sentence that names every feature.
    static var summary: String {
        """
        Pictures of your menu bar items in the holzBar Shelf, the search and the Menu Bar Layout pane \
        (on macOS 27 taken once per item), and the wallpaper beside a menu bar shape.
        """
    }
}
