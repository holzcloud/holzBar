//
//  AdvancedSettings.swift
//  holzBar
//

import Observation
import SwiftUI

// MARK: - AdvancedSettings

/// Model for the app's Advanced settings.
@MainActor
@Observable
final class AdvancedSettings {
    /// A Boolean value that indicates whether the always-hidden section
    /// is enabled.
    var enableAlwaysHiddenSection = false {
        didSet {
            Defaults.set(enableAlwaysHiddenSection, forKey: .enableAlwaysHiddenSection)
        }
    }

    /// A Boolean value that indicates whether to show all sections when
    /// the user is dragging items in the menu bar.
    var showAllSectionsOnUserDrag = true {
        didSet {
            Defaults.set(showAllSectionsOnUserDrag, forKey: .showAllSectionsOnUserDrag)
        }
    }

    /// The display style for section divider control items.
    var sectionDividerStyle: SectionDividerStyle = .noDivider {
        didSet {
            Defaults.set(sectionDividerStyle.rawValue, forKey: .sectionDividerStyle)
        }
    }

    /// A Boolean value that indicates whether the application menus
    /// should be hidden if needed to show all menu bar items.
    var hideApplicationMenus = true {
        didSet {
            Defaults.set(hideApplicationMenus, forKey: .hideApplicationMenus)
        }
    }

    /// A Boolean value that indicates whether holzBar never shows a Dock icon, so the
    /// application menus are not hidden (macOS hides them only for an app in the Dock).
    var keepsDockIconHidden = true {
        didSet {
            Defaults.set(keepsDockIconHidden, forKey: .keepsDockIconHidden)
        }
    }

    /// A Boolean value that indicates whether to show a context menu
    /// when the user right-clicks the menu bar.
    var enableSecondaryContextMenu = true {
        didSet {
            Defaults.set(enableSecondaryContextMenu, forKey: .enableSecondaryContextMenu)
        }
    }

    /// The delay before showing on hover.
    var showOnHoverDelay: TimeInterval = 0.2 {
        didSet {
            Defaults.set(showOnHoverDelay, forKey: .showOnHoverDelay)
        }
    }

    /// Time interval to temporarily show items for.
    var tempShowInterval: TimeInterval = 15 {
        didSet {
            Defaults.set(tempShowInterval, forKey: .tempShowInterval)
        }
    }

    /// The section that new menu bar items are placed in.
    var newItemsPlacement: NewItemsPlacement = .systemDefault {
        didSet {
            Defaults.set(newItemsPlacement.rawValue, forKey: .newItemsPlacement)
        }
    }

    /// A Boolean value that indicates whether Live Activities stay in the
    /// visible section.
    var keepLiveActivitiesVisible = true {
        didSet {
            Defaults.set(keepLiveActivitiesVisible, forKey: .keepLiveActivitiesVisible)
        }
    }

    /// A Boolean value that indicates whether Zen mode turns on while a display is
    /// mirrored or the screen is shared (`PresentationMonitor`).
    var autoZenWhileSharingScreen = false {
        didSet {
            Defaults.set(autoZenWhileSharingScreen, forKey: .autoZenWhileSharingScreen)
        }
    }

    /// The shared app state.
    @ObservationIgnored private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    ///
    /// Each setting saves itself in its `didSet`; loading assigns the stored values.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .enableAlwaysHiddenSection, assign: &enableAlwaysHiddenSection)
        Defaults.ifPresent(key: .showAllSectionsOnUserDrag, assign: &showAllSectionsOnUserDrag)
        Defaults.ifPresent(key: .hideApplicationMenus, assign: &hideApplicationMenus)
        Defaults.ifPresent(key: .keepsDockIconHidden, assign: &keepsDockIconHidden)
        Defaults.ifPresent(key: .enableSecondaryContextMenu, assign: &enableSecondaryContextMenu)
        Defaults.ifPresent(key: .showOnHoverDelay, assign: &showOnHoverDelay)
        Defaults.ifPresent(key: .tempShowInterval, assign: &tempShowInterval)
        Defaults.ifPresent(key: .keepLiveActivitiesVisible, assign: &keepLiveActivitiesVisible)
        Defaults.ifPresent(key: .autoZenWhileSharingScreen, assign: &autoZenWhileSharingScreen)

        Defaults.ifPresent(key: .sectionDividerStyle) { rawValue in
            if let style = SectionDividerStyle(rawValue: rawValue) {
                sectionDividerStyle = style
            }
        }

        Defaults.ifPresent(key: .newItemsPlacement) { rawValue in
            if let placement = NewItemsPlacement(rawValue: rawValue) {
                newItemsPlacement = placement
            }
        }
    }
}

// MARK: - SectionDividerStyle

enum SectionDividerStyle: Int, CaseIterable, Identifiable {
    case noDivider = 0
    case chevron = 1

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noDivider: "None"
        case .chevron: "Chevron"
        }
    }
}

// MARK: - NewItemsPlacement

/// Where holzBar places menu bar items it has not seen before.
enum NewItemsPlacement: Int, CaseIterable, Identifiable {
    /// Leave new items where macOS puts them.
    case systemDefault = 0
    /// Move new items to the visible section.
    case visible = 1
    /// Move new items to the hidden section.
    case hidden = 2
    /// Move new items to the always-hidden section.
    case alwaysHidden = 3

    var id: Int { rawValue }

    /// The section that new items are placed in, or `nil` to leave them alone.
    var section: MenuBarSection.Name? {
        switch self {
        case .systemDefault: nil
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .systemDefault: "Where macOS puts them"
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always-Hidden"
        }
    }
}
