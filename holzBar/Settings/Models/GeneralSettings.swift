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

    /// A Boolean value that indicates whether holzBar's icon shows a dot while
    /// another app uses the microphone or a camera, on macOS 27, where Control
    /// Centre's indicator is not drawn while holzBar hides items.
    var holzBarIconShowsCaptureDot = true {
        didSet {
            Defaults.set(holzBarIconShowsCaptureDot, forKey: .holzBarIconShowsCaptureDot)
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

    /// Whether the holzBar Shelf hangs directly below the menu bar or floats a little below it.
    var shelfStyle: HolzBarShelfStyle = .attached {
        didSet {
            Defaults.set(shelfStyle.rawValue, forKey: .shelfStyle)
        }
    }

    /// How the holzBar Shelf arranges its items.
    var shelfLayout: ShelfLayout = .row {
        didSet {
            Defaults.set(shelfLayout.rawValue, forKey: .shelfLayout)
        }
    }

    /// How showing and hiding looks (`RevealAnimationStyle`). With Reduce Motion on nothing
    /// animates, whatever this says.
    var revealAnimationStyle = RevealAnimationStyle.standard {
        didSet {
            Defaults.set(revealAnimationStyle.rawValue, forKey: .revealAnimationStyle)
        }
    }

    /// A Boolean value that indicates whether a click on the clock opens Notification Center
    /// while items are hidden (macOS 27).
    var clockOpensNotificationCenter = true {
        didSet {
            Defaults.set(clockOpensNotificationCenter, forKey: .clockOpensNotificationCenter)
        }
    }

    /// What each display does with the hidden items, by display UUID. The display under the
    /// pointer wins (`DisplayBehavior`).
    var displayBehaviors = DisplayBehaviors() {
        didSet {
            Defaults.set(displayBehaviors.stored, forKey: .displayBehaviors)
        }
    }

    /// A Boolean value that indicates whether a change in the Menu Bar Layout pane moves the
    /// item at once. Off, the pane draws a draft and Apply lays the bar out.
    var appliesLayoutChangesImmediately = false {
        didSet {
            Defaults.set(appliesLayoutChangesImmediately, forKey: .appliesLayoutChangesImmediately)
        }
    }

    /// A Boolean value that indicates whether the search offers category chips. While it is off
    /// nothing is classified and no application bundle is read.
    var smartCategories = true {
        didSet {
            Defaults.set(smartCategories, forKey: .smartCategories)
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

    /// A Boolean value that indicates whether typing in the holzBar Shelf finds an item. The
    /// Shelf takes the keyboard when a hotkey opens it.
    var shelfFindsByTyping = true {
        didSet {
            Defaults.set(shelfFindsByTyping, forKey: .shelfFindsByTyping)
        }
    }

    /// Whether the holzBar Shelf opens the fold of the always-hidden items folded each time or
    /// as the user left it.
    var shelfAlwaysHiddenFold: ShelfAlwaysHiddenFold = .foldedEachTime {
        didSet {
            Defaults.set(shelfAlwaysHiddenFold.rawValue, forKey: .shelfAlwaysHiddenFold)
        }
    }

    /// Whether the user left the fold of the always-hidden items open the last time. The Shelf
    /// writes it when the fold is opened or closed; it stays on this Mac.
    var shelfAlwaysHiddenFoldOpen = false {
        didSet {
            Defaults.set(shelfAlwaysHiddenFoldOpen, forKey: .shelfAlwaysHiddenFoldOpen)
        }
    }

    /// A Boolean value that indicates whether the holzBar Shelf also lists the applications
    /// that are not running, dimmed, and launches one that is clicked.
    var shelfShowsClosedApps = false {
        didSet {
            Defaults.set(shelfShowsClosedApps, forKey: .shelfShowsClosedApps)
        }
    }

    /// A Boolean value that indicates whether a tile of the holzBar Shelf can be dragged to put
    /// the items in order, into another section or onto the menu bar.
    var shelfDragsTiles = true {
        didSet {
            Defaults.set(shelfDragsTiles, forKey: .shelfDragsTiles)
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
            appState?.spacingManager.offset = spacingOffsetPoints
        }
    }

    /// ``itemSpacingOffset`` as whole points, kept in the slider's range. `Int(_:)` traps on
    /// a value out of `Int`'s range or not finite, which an imported file, or any
    /// process writing holzBar's defaults, could store.
    private var spacingOffsetPoints: Int {
        Int(Defaults.Key.itemSpacingOffset.clamped(itemSpacingOffset, fallback: 0).rounded())
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
        appState.spacingManager.offset = spacingOffsetPoints
    }

    /// Loads the model's initial state.
    private func loadInitialState() {
        Defaults.ifPresent(key: .showHolzBarIcon, assign: &showHolzBarIcon)
        Defaults.ifPresent(key: .holzBarIconShowsCaptureDot, assign: &holzBarIconShowsCaptureDot)
        Defaults.ifPresent(key: .customHolzBarIconIsTemplate, assign: &customHolzBarIconIsTemplate)
        Defaults.ifPresent(key: .useShelf, assign: &useShelf)
        Defaults.ifPresent(key: .showOnClick, assign: &showOnClick)
        Defaults.ifPresent(key: .showOnHover, assign: &showOnHover)
        Defaults.ifPresent(key: .showOnScroll, assign: &showOnScroll)
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
        Defaults.ifPresent(key: .shelfStyle) { (rawValue: Int) in
            shelfStyle = HolzBarShelfStyle.stored(rawValue)
        }
        Defaults.ifPresent(key: .shelfLayout) { rawValue in
            if let layout = ShelfLayout(rawValue: rawValue) {
                shelfLayout = layout
            }
        }
        if let raw = Defaults.object(forKey: .revealAnimationStyle) as? Int {
            revealAnimationStyle = RevealAnimationStyle.stored(raw)
        } else {
            // Earlier versions had a switch for the menu bar and one for the holzBar Shelf.
            revealAnimationStyle = RevealAnimationStyle.migrated(
                animatesShowHide: Defaults.object(forKey: .animatesShowHide) as? Bool,
                animatesShelf: Defaults.object(forKey: .animatesShelf) as? Bool
            )
        }
        if let stored = Defaults.dictionary(forKey: .displayBehaviors) {
            displayBehaviors = DisplayBehaviors(stored: stored)
        }
        Defaults.ifPresent(key: .clockOpensNotificationCenter, assign: &clockOpensNotificationCenter)
        Defaults.ifPresent(key: .appliesLayoutChangesImmediately, assign: &appliesLayoutChangesImmediately)
        Defaults.ifPresent(key: .showsNotchOverflowInShelf, assign: &showsNotchOverflowInShelf)
        Defaults.ifPresent(key: .smartCategories, assign: &smartCategories)
        Defaults.ifPresent(key: .shelfFindsByTyping, assign: &shelfFindsByTyping)
        Defaults.ifPresent(key: .shelfAlwaysHiddenFoldOpen, assign: &shelfAlwaysHiddenFoldOpen)
        Defaults.ifPresent(key: .shelfShowsClosedApps, assign: &shelfShowsClosedApps)
        Defaults.ifPresent(key: .shelfDragsTiles, assign: &shelfDragsTiles)
        Defaults.ifPresent(key: .shelfAlwaysHiddenFold) { (rawValue: Int) in
            shelfAlwaysHiddenFold = ShelfAlwaysHiddenFold.stored(rawValue)
        }
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
