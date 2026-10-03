//
//  GeneralSettings.swift
//  holzBar
//

import Observation
import OSLog
import SwiftUI

// MARK: - GeneralSettings

/// Model for the app's General settings.
@MainActor
@Observable
final class GeneralSettings {
    /// A Boolean value that indicates whether the holzBar icon
    /// should be shown.
    var showHolzBarIcon = true {
        didSet {
            Defaults.set(showHolzBarIcon, forKey: .showHolzBarIcon)
        }
    }

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    var holzBarIcon: ControlItemImageSet = .defaultHolzBarIcon {
        didSet {
            if case .custom = holzBarIcon.name {
                lastCustomHolzBarIcon = holzBarIcon
            }
            do {
                let data = try encoder.encode(holzBarIcon)
                Defaults.set(data, forKey: .holzBarIcon)
            } catch {
                Logger.serialization.error("Error encoding holzBar icon: \(error, privacy: .private)")
            }
        }
    }

    /// The last user-selected custom holzBar icon.
    var lastCustomHolzBarIcon: ControlItemImageSet?

    /// A Boolean value that indicates whether custom holzBar icons
    /// should be rendered as template images.
    var customHolzBarIconIsTemplate = false {
        didSet {
            Defaults.set(customHolzBarIconIsTemplate, forKey: .customHolzBarIconIsTemplate)
        }
    }

    /// A Boolean value that indicates whether to show hidden items
    /// in a separate bar below the menu bar.
    var useShelf = false {
        didSet {
            Defaults.set(useShelf, forKey: .useShelf)
        }
    }

    /// The location where the holzBar Shelf appears.
    var shelfLocation: HolzBarShelfLocation = .dynamic {
        didSet {
            Defaults.set(shelfLocation.rawValue, forKey: .shelfLocation)
        }
    }

    /// The displays the holzBar Shelf is used on.
    var shelfDisplays: HolzBarShelfDisplays = .all {
        didSet {
            Defaults.set(shelfDisplays.rawValue, forKey: .shelfDisplays)
        }
    }

    /// A Boolean value that indicates whether the holzBar Shelf also shows the
    /// visible items that the notch covers.
    var showsNotchOverflowInShelf = true {
        didSet {
            Defaults.set(showsNotchOverflowInShelf, forKey: .showsNotchOverflowInShelf)
        }
    }

    /// A Boolean value that indicates whether the holzBar Shelf is used right now:
    /// it is turned on, and the display under the mouse pointer is one it is
    /// used on.
    var usesShelf: Bool {
        useShelf && shelfDisplays.includes(NSScreen.screenWithMouse ?? NSScreen.main)
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer clicks in an empty
    /// area of the menu bar.
    var showOnClick = true {
        didSet {
            Defaults.set(showOnClick, forKey: .showOnClick)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    var showOnHover = false {
        didSet {
            Defaults.set(showOnHover, forKey: .showOnHover)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    var showOnScroll = true {
        didSet {
            Defaults.set(showOnScroll, forKey: .showOnScroll)
        }
    }

    /// The offset to apply to the menu bar item spacing and padding.
    var itemSpacingOffset: Double = 0 {
        didSet {
            Defaults.set(itemSpacingOffset, forKey: .itemSpacingOffset)
            appState?.spacingManager.offset = Int(itemSpacingOffset)
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    var autoRehide = true {
        didSet {
            Defaults.set(autoRehide, forKey: .autoRehide)
        }
    }

    /// A strategy that determines how the auto-rehide feature works.
    var rehideStrategy: RehideStrategy = .smart {
        didSet {
            Defaults.set(rehideStrategy.rawValue, forKey: .rehideStrategy)
        }
    }

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    var rehideInterval: TimeInterval = 15 {
        didSet {
            Defaults.set(rehideInterval, forKey: .rehideInterval)
        }
    }

    /// Encoder for properties.
    @ObservationIgnored private let encoder = JSONEncoder()

    /// Decoder for properties.
    @ObservationIgnored private let decoder = JSONDecoder()

    /// The shared app state.
    @ObservationIgnored private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    ///
    /// Each setting saves itself in its `didSet`; loading assigns the stored values.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        appState.spacingManager.offset = Int(itemSpacingOffset)
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .showHolzBarIcon, assign: &showHolzBarIcon)
        Defaults.ifPresent(key: .customHolzBarIconIsTemplate, assign: &customHolzBarIconIsTemplate)
        Defaults.ifPresent(key: .useShelf, assign: &useShelf)
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
        Defaults.ifPresent(key: .itemSpacingOffset, assign: &itemSpacingOffset)
        Defaults.ifPresent(key: .autoRehide, assign: &autoRehide)
        Defaults.ifPresent(key: .rehideInterval, assign: &rehideInterval)

        Defaults.ifPresent(key: .shelfLocation) { rawValue in
            if let location = HolzBarShelfLocation(rawValue: rawValue) {
                shelfLocation = location
            }
        }
        Defaults.ifPresent(key: .showsNotchOverflowInShelf, assign: &showsNotchOverflowInShelf)
        Defaults.ifPresent(key: .shelfDisplays) { rawValue in
            if let displays = HolzBarShelfDisplays(rawValue: rawValue) {
                shelfDisplays = displays
            }
        }
        Defaults.ifPresent(key: .rehideStrategy) { rawValue in
            if let strategy = RehideStrategy(rawValue: rawValue) {
                rehideStrategy = strategy
            }
        }

        if let data = Defaults.data(forKey: .holzBarIcon) {
            do {
                holzBarIcon = try decoder.decode(ControlItemImageSet.self, from: data)
            } catch {
                Logger.serialization.error("Error decoding holzBar icon: \(error, privacy: .private)")
            }
            if case .custom = holzBarIcon.name {
                lastCustomHolzBarIcon = holzBarIcon
            }
        }
    }
}

// MARK: - RehideStrategy

/// A type that determines how the auto-rehide feature works.
enum RehideStrategy: Int, CaseIterable, Identifiable {
    /// Menu bar items are rehidden using a smart algorithm.
    case smart = 0
    /// Menu bar items are rehidden after a given time interval.
    case timed = 1
    /// Menu bar items are rehidden when the focused app changes.
    case focusedApp = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .smart: "Smart"
        case .timed: "Timed"
        case .focusedApp: "Focused app"
        }
    }
}
