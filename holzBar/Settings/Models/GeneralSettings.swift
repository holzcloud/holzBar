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
            if !isLoadingStoredValues {
                Defaults.set(showHolzBarIcon, forKey: .showHolzBarIcon)
            }
        }
    }

    /// A Boolean value that indicates whether holzBar's icon shows a dot while
    /// another app uses the microphone or a camera, on macOS 27, where Control
    /// Centre's indicator is not drawn while holzBar hides items.
    var holzBarIconShowsCaptureDot = true {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(holzBarIconShowsCaptureDot, forKey: .holzBarIconShowsCaptureDot)
            }
        }
    }

    /// An icon to show in the menu bar, with a different image
    /// for when items are visible or hidden.
    var holzBarIcon: ControlItemImageSet = .defaultHolzBarIcon {
        didSet {
            if case .custom = holzBarIcon.name {
                lastCustomHolzBarIcon = holzBarIcon
            }
            if !isLoadingStoredValues {
                do {
                    let data = try encoder.encode(holzBarIcon)
                    Defaults.set(data, forKey: .holzBarIcon)
                } catch {
                    Logger.serialization.error("Error encoding holzBar icon: \(error, privacy: .private)")
                }
            }
        }
    }

    /// The last user-selected custom holzBar icon.
    var lastCustomHolzBarIcon: ControlItemImageSet?

    /// A Boolean value that indicates whether custom holzBar icons
    /// should be rendered as template images.
    var customHolzBarIconIsTemplate = false {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(customHolzBarIconIsTemplate, forKey: .customHolzBarIconIsTemplate)
            }
        }
    }

    /// A Boolean value that indicates whether to show hidden items
    /// in a separate bar below the menu bar.
    var useShelf = false {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(useShelf, forKey: .useShelf)
            }
        }
    }

    /// The location where the holzBar Shelf appears.
    var shelfLocation: HolzBarShelfLocation = .dynamic {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(shelfLocation.rawValue, forKey: .shelfLocation)
            }
        }
    }

    /// The displays the holzBar Shelf is used on.
    var shelfDisplays: HolzBarShelfDisplays = .all {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(shelfDisplays.rawValue, forKey: .shelfDisplays)
            }
        }
    }

    /// A Boolean value that indicates whether the holzBar Shelf also shows the
    /// visible items that the notch covers.
    var showsNotchOverflowInShelf = true {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(showsNotchOverflowInShelf, forKey: .showsNotchOverflowInShelf)
            }
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
            if !isLoadingStoredValues {
                Defaults.set(showOnClick, forKey: .showOnClick)
            }
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown when the mouse pointer hovers over an
    /// empty area of the menu bar.
    var showOnHover = false {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(showOnHover, forKey: .showOnHover)
            }
        }
    }

    /// A Boolean value that indicates whether the hidden section
    /// should be shown or hidden when the user scrolls in the
    /// menu bar.
    var showOnScroll = true {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(showOnScroll, forKey: .showOnScroll)
            }
        }
    }

    /// The offset to apply to the menu bar item spacing and padding.
    var itemSpacingOffset: Double = 0 {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(itemSpacingOffset, forKey: .itemSpacingOffset)
            }
            appState?.spacingManager.offset = spacingOffsetPoints
        }
    }

    /// ``itemSpacingOffset`` as whole points, kept in the slider's range. `Int(_:)` traps on
    /// a value out of `Int`'s range or not finite, which an imported or synced file, or any
    /// process writing holzBar's defaults, could store.
    private var spacingOffsetPoints: Int {
        Int(Defaults.Key.itemSpacingOffset.clamped(itemSpacingOffset, fallback: 0).rounded())
    }

    /// A Boolean value that indicates whether the hidden section
    /// should automatically rehide.
    var autoRehide = true {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(autoRehide, forKey: .autoRehide)
            }
        }
    }

    /// A strategy that determines how the auto-rehide feature works.
    var rehideStrategy: RehideStrategy = .smart {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(rehideStrategy.rawValue, forKey: .rehideStrategy)
            }
        }
    }

    /// A time interval for the auto-rehide feature when its rule
    /// is ``RehideStrategy/timed``.
    var rehideInterval: TimeInterval = 15 {
        didSet {
            if !isLoadingStoredValues {
                Defaults.set(rehideInterval, forKey: .rehideInterval)
            }
        }
    }

    /// Encoder for properties.
    @ObservationIgnored private let encoder = JSONEncoder()

    /// Decoder for properties.
    @ObservationIgnored private let decoder = JSONDecoder()

    /// A Boolean value that indicates whether ``loadInitialState()`` is assigning the stored
    /// values. While it is, no `didSet` saves: a launch never rewrites a stored synced setting
    /// the user did not change (analysis §4.9 item 2).
    @ObservationIgnored private var isLoadingStoredValues = false

    /// The shared app state.
    @ObservationIgnored private(set) weak var appState: AppState?

    /// Performs the initial setup of the model.
    ///
    /// Each setting saves itself in its `didSet`; loading assigns the stored values without saving.
    func performSetup(with appState: AppState) {
        self.appState = appState
        loadInitialState()
        appState.spacingManager.offset = spacingOffsetPoints
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        isLoadingStoredValues = true
        defer {
            isLoadingStoredValues = false
        }
        Defaults.ifPresent(key: .showHolzBarIcon, assign: &showHolzBarIcon)
        Defaults.ifPresent(key: .holzBarIconShowsCaptureDot, assign: &holzBarIconShowsCaptureDot)
        Defaults.ifPresent(key: .customHolzBarIconIsTemplate, assign: &customHolzBarIconIsTemplate)
        Defaults.ifPresent(key: .useShelf, assign: &useShelf)
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
        // Out-of-range values are clamped when used, in memory only, and never by rewriting
        // storage (analysis §4.9 item 2).
        Defaults.ifPresent(key: .itemSpacingOffset) { (value: Double) in
            itemSpacingOffset = Defaults.Key.itemSpacingOffset.clamped(value, fallback: itemSpacingOffset)
        }
        Defaults.ifPresent(key: .autoRehide, assign: &autoRehide)
        Defaults.ifPresent(key: .rehideInterval) { (value: Double) in
            rehideInterval = Defaults.Key.rehideInterval.clamped(value, fallback: rehideInterval)
        }

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
