//
//  Defaults.swift
//  holzBar
//

import Foundation

nonisolated enum Defaults {
    /// Returns a dictionary containing the keys and values for
    /// the defaults meant to be seen by all applications.
    static var globalDomain: [String: Any] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
    }

    /// Returns the object for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func object(forKey key: Key) -> Any? {
        UserDefaults.standard.object(forKey: key.rawValue)
    }

    /// Returns the string for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func string(forKey key: Key) -> String? {
        UserDefaults.standard.string(forKey: key.rawValue)
    }

    /// Returns the array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func array(forKey key: Key) -> [Any]? {
        UserDefaults.standard.array(forKey: key.rawValue)
    }

    /// Returns the dictionary for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func dictionary(forKey key: Key) -> [String: Any]? {
        UserDefaults.standard.dictionary(forKey: key.rawValue)
    }

    /// Returns the data for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func data(forKey key: Key) -> Data? {
        UserDefaults.standard.data(forKey: key.rawValue)
    }

    /// Returns the string array for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func stringArray(forKey key: Key) -> [String]? {
        UserDefaults.standard.stringArray(forKey: key.rawValue)
    }

    /// Returns the integer value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func integer(forKey key: Key) -> Int {
        UserDefaults.standard.integer(forKey: key.rawValue)
    }

    /// Returns the single precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func float(forKey key: Key) -> Float {
        UserDefaults.standard.float(forKey: key.rawValue)
    }

    /// Returns the double precision floating point value for
    /// the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func double(forKey key: Key) -> Double {
        UserDefaults.standard.double(forKey: key.rawValue)
    }

    /// Returns the Boolean value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func bool(forKey key: Key) -> Bool {
        UserDefaults.standard.bool(forKey: key.rawValue)
    }

    /// Returns the url for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to retrieve the value for.
    static func url(forKey key: Key) -> URL? {
        UserDefaults.standard.url(forKey: key.rawValue)
    }

    /// Sets the value for the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to set the value for.
    static func set(_ value: Any?, forKey key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    /// Removes the value of the specified key.
    ///
    /// - Parameter key: The key in the UserDefaults database
    ///   to remove the value for.
    static func removeObject(forKey key: Key) {
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }

    /// Retrieves the value for the given key, and, if it is
    /// present, assigns it to the given `inout` parameter.
    static func ifPresent<Value>(key: Key, assign value: inout Value) {
        if let found = object(forKey: key) as? Value {
            value = found
        }
    }

    /// Retrieves the value for the given key, and, if it is
    /// present, performs the given closure.
    static func ifPresent<Value>(key: Key, body: (Value) throws -> Void) rethrows {
        if let found = object(forKey: key) as? Value {
            try body(found)
        }
    }
}

nonisolated extension Defaults {
    /// The keys holzBar stores its settings under.
    ///
    /// Every key declares the kind of value it holds (``settingsKind``), so an imported
    /// settings file can only set holzBar's own keys, with values of the
    /// expected kind (``SettingsSchema``).
    nonisolated enum Key: String, CaseIterable {
        // MARK: General Settings

        /// The stored strings keep the names that earlier versions of the app
        /// stored these settings under, so imported settings keep working.
        case showHolzBarIcon = "ShowIceIcon"
        case holzBarIcon = "IceIcon"
        case customHolzBarIconIsTemplate = "CustomIceIconIsTemplate"
        case useShelf = "UseIceBar"
        case shelfLocation = "IceBarLocation"
        case shelfDisplays = "IceBarDisplays"
        case showsNotchOverflowInShelf = "ShowsNotchOverflowInIceBar"
        case showOnClick = "ShowOnClick"
        case showOnHover = "ShowOnHover"
        case showOnScroll = "ShowOnScroll"
        case autoRehide = "AutoRehide"
        case rehideStrategy = "RehideStrategy"
        case rehideInterval = "RehideInterval"
        case itemSpacingOffset = "ItemSpacingOffset"
        /// macOS 27: a dot on holzBar's icon while another app uses the microphone or a camera.
        case holzBarIconShowsCaptureDot = "HolzBarIconShowsCaptureDot"

        // MARK: Hotkeys Settings
        case hotkeys = "Hotkeys"

        // MARK: Advanced Settings
        case enableAlwaysHiddenSection = "EnableAlwaysHiddenSection"
        case showAllSectionsOnUserDrag = "ShowAllSectionsOnUserDrag"
        case sectionDividerStyle = "SectionDividerStyle"
        case hideApplicationMenus = "HideApplicationMenus"
        case keepsDockIconHidden = "KeepsDockIconHidden"
        case enableSecondaryContextMenu = "EnableSecondaryContextMenu"
        case showOnHoverDelay = "ShowOnHoverDelay"
        case tempShowInterval = "TempShowInterval"
        case newItemsPlacement = "NewItemsPlacement"
        case keepLiveActivitiesVisible = "KeepLiveActivitiesVisible"
        case autoZenWhileSharingScreen = "AutoZenWhileSharingScreen"
        case openHiddenItemsInMenuBar = "OpenHiddenItemsInMenuBar"
        /// The identity keys of the items shown for a moment when they change.
        case revealOnChangeItems = "RevealOnChangeItems"
        /// The image each item shows, by identity: "app" or "file:<name>.png".
        case itemIcons = "ItemIcons"
        case layoutProfiles = "LayoutProfiles"
        case currentLayoutProfile = "CurrentLayoutProfile"
        /// Left by the 0.0.7 betas. Nothing reads or writes it any more, and the stored value stays.
        case syncsSettingsWithICloud = "SyncsSettingsWithICloud"
        case itemGroups = "ItemGroups"
        case spacerCount = "SpacerCount"
        case spacerWidth = "SpacerWidth"
        case revealRules = "RevealRules"
        /// The automation rules, as JSON (`AutomationRule`).
        case automationRules = "AutomationRules"
        case knownItemTags = "KnownItemTags"
        case knownApplications27 = "KnownApplications27"
        /// The section of each item before macOS 27, keyed by its identity (`ItemIdentity`):
        /// 0 visible, 1 hidden, 2 always hidden.
        case itemSections = "ItemSections"
        /// The namespaces whose item titles change beyond their numbers (`ItemIdentity`).
        case titleChangingItemOwners = "TitleChangingItemOwners"

        // MARK: Appearance Settings
        case menuBarAppearanceConfigurationV2 = "MenuBarAppearanceConfigurationV2"

        // MARK: macOS 27
        case macOS27Layout = "MacOS27Layout"
        case macOS27LayoutSeeded = "MacOS27LayoutSeeded"
        case macOS27ClickRestoreDelay = "MacOS27ClickRestoreDelay"
        case macOS27ShelfWaitsForRefresh = "MacOS27IceBarWaitsForRefresh"

        // MARK: Debugging
        /// Loses the round trip of every move and click event barrier before macOS 27: the
        /// entry event is dropped, so the real event never reaches the item, the exit event
        /// never comes back and each barrier times out; shows that holzBar recovers from a
        /// lost event. Hidden:
        /// `defaults write com.holzcloud.holzBar DebugDropsBarrierExitEvent -bool true`.
        /// Never exported or imported.
        case debugDropsBarrierExitEvent = "DebugDropsBarrierExitEvent"
        /// Blocks every item image capture before macOS 27 forever, so each one times out;
        /// shows that holzBar recovers from a stuck capture and stops capturing after three.
        /// Hidden: `defaults write com.holzcloud.holzBar DebugHangsItemImageCapture -bool true`.
        /// Never exported or imported.
        case debugHangsItemImageCapture = "DebugHangsItemImageCapture"

        // MARK: Migration
        case hasMigrated0_8_0 = "hasMigrated0_8_0"
        case hasMigrated0_10_0 = "hasMigrated0_10_0"
        case hasMigrated0_10_1 = "hasMigrated0_10_1"
        case hasMigrated0_11_10 = "hasMigrated0_11_10"
        case hasMigrated0_11_13 = "hasMigrated0_11_13"
        case hasMigrated0_11_13_1 = "hasMigrated0_11_13_1"
        /// Set once holzBar has looked for the settings of an app it replaces.
        /// The stored key keeps its earlier name.
        case hasImportedPreviousSettings = "HasImportedIceSettings"

        // MARK: Deprecated (Appearance Settings)
        case menuBarHasBorder = "MenuBarHasBorder"
        case menuBarBorderColor = "MenuBarBorderColor"
        case menuBarBorderWidth = "MenuBarBorderWidth"
        case menuBarHasShadow = "MenuBarHasShadow"
        case menuBarTintKind = "MenuBarTintKind"
        case menuBarTintColor = "MenuBarTintColor"
        case menuBarTintGradient = "MenuBarTintGradient"
        case menuBarShapeKind = "MenuBarShapeKind"
        case menuBarFullShapeInfo = "MenuBarFullShapeInfo"
        case menuBarSplitShapeInfo = "MenuBarSplitShapeInfo"
        case menuBarAppearanceConfiguration = "MenuBarAppearanceConfiguration"

        // MARK: Deprecated (Advanced Settings)
        case showSectionDividers = "ShowSectionDividers"
        case canToggleAlwaysHiddenSection = "CanToggleAlwaysHiddenSection"

        // MARK: Deprecated (Other)
        case sections = "Sections"
    }
}

// MARK: - Value Kinds

nonisolated extension Defaults.Key {
    /// The kind of value stored under this key.
    ///
    /// The switch has no `default`, so a new key must declare its kind before it
    /// can be built; imported settings are checked against these kinds.
    var settingsKind: SettingsSchema.Kind {
        switch self {
        case .showHolzBarIcon,
            .customHolzBarIconIsTemplate,
            .useShelf,
            .showsNotchOverflowInShelf,
            .showOnClick,
            .showOnHover,
            .showOnScroll,
            .autoRehide,
            .holzBarIconShowsCaptureDot,
            .enableAlwaysHiddenSection,
            .showAllSectionsOnUserDrag,
            .hideApplicationMenus,
            .keepsDockIconHidden,
            .enableSecondaryContextMenu,
            .keepLiveActivitiesVisible,
            .autoZenWhileSharingScreen,
            .openHiddenItemsInMenuBar,
            .syncsSettingsWithICloud,
            .macOS27LayoutSeeded,
            .macOS27ShelfWaitsForRefresh,
            .debugDropsBarrierExitEvent,
            .debugHangsItemImageCapture,
            .hasMigrated0_8_0,
            .hasMigrated0_10_0,
            .hasMigrated0_10_1,
            .hasMigrated0_11_10,
            .hasMigrated0_11_13,
            .hasMigrated0_11_13_1,
            .hasImportedPreviousSettings,
            .menuBarHasBorder,
            .menuBarHasShadow,
            .showSectionDividers,
            .canToggleAlwaysHiddenSection:
            .bool
        case .shelfLocation,
            .shelfDisplays,
            .rehideStrategy,
            .rehideInterval,
            .itemSpacingOffset,
            .sectionDividerStyle,
            .showOnHoverDelay,
            .tempShowInterval,
            .newItemsPlacement,
            .spacerCount,
            .spacerWidth,
            .macOS27ClickRestoreDelay,
            .menuBarBorderWidth,
            .menuBarTintKind:
            .number
        case .holzBarIcon,
            .layoutProfiles,
            .automationRules,
            .itemGroups,
            .menuBarAppearanceConfigurationV2,
            .menuBarBorderColor,
            .menuBarTintColor,
            .menuBarTintGradient,
            .menuBarShapeKind,
            .menuBarFullShapeInfo,
            .menuBarSplitShapeInfo,
            .menuBarAppearanceConfiguration,
            .sections:
            .data
        case .currentLayoutProfile:
            .string
        case .knownItemTags,
            .knownApplications27,
            .titleChangingItemOwners,
            .revealOnChangeItems:
            .stringArray
        case .hotkeys,
            .revealRules,
            .macOS27Layout,
            .itemSections,
            .itemIcons:
            // Their readers cast the contents themselves, so the kind is checked
            // only at the top level.
            .dictionary
        }
    }

    /// The values a numeric setting may take: the range of its slider, stepper or
    /// choices. `nil` for the keys that hold no number.
    ///
    /// Imported values outside it are clamped or refused
    /// (``SettingsSchema/NumberRule``), and the models clamp what they read from the
    /// defaults, which any process of the user can write.
    var numberRule: SettingsSchema.NumberRule? {
        switch self {
        case .itemSpacingOffset:
            .clamped(-16...16)
        case .rehideInterval, .tempShowInterval:
            .clamped(0...30)
        case .showOnHoverDelay:
            .clamped(0...1)
        case .spacerWidth:
            .clamped(4...60)
        case .macOS27ClickRestoreDelay:
            // Milliseconds, read as a whole number and kept in 30...2000 by its reader.
            .clamped(0...2000)
        case .menuBarBorderWidth:
            .clamped(1...3)
        case .spacerCount:
            .wholeNumber(0...10)
        case .shelfLocation,
            .shelfDisplays,
            .rehideStrategy,
            .sectionDividerStyle,
            .newItemsPlacement,
            .menuBarTintKind:
            // The raw value of a choice; its reader also refuses unknown ones.
            .wholeNumber(0...15)
        default:
            nil
        }
    }

    /// A number read from the defaults under this key, kept in the range of its setting
    /// (``numberRule``); `fallback` when it is not finite.
    ///
    /// The defaults can hold anything: an imported file, or any process of the
    /// user, may have written them. A value out of range trapped where the app turns it into
    /// an `Int` or a `Duration`.
    func clamped(_ value: Double, fallback: Double) -> Double {
        guard let numberRule else {
            return value.isFinite ? value : fallback
        }
        return numberRule.clamp(value, fallback: fallback)
    }

    /// Keys that stay on this Mac: never exported or imported.
    ///
    /// The key the 0.0.7 betas used for settings sync stays here too, so a settings file
    /// never sets it. The debug defaults stay on this Mac as well.
    static let localOnlyKeys: Set<Defaults.Key> = [
        .syncsSettingsWithICloud,
        .debugDropsBarrierExitEvent,
        .debugHangsItemImageCapture,
    ]

    /// The stored key names an imported settings file may set, with the
    /// kind of value each one takes. Every key except the ``localOnlyKeys``.
    static let importableKinds: [String: SettingsSchema.Kind] = Dictionary(
        uniqueKeysWithValues: allCases.filter { !localOnlyKeys.contains($0) }.map { ($0.rawValue, $0.settingsKind) }
    )

    /// The values the numeric keys an imported settings file may set can take.
    static let importableNumberRules: [String: SettingsSchema.NumberRule] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { key in
            key.numberRule.map { (key.rawValue, $0) }
        }
    )

    /// Splits settings read from outside the app into the values holzBar applies and the
    /// keys it ignores: only holzBar's own keys that may be imported, with a value of the
    /// expected kind, numbers within their range (``SettingsSchema``).
    static func validatedSettings(_ settings: [String: Any]) -> (accepted: [String: Any], ignored: [String]) {
        SettingsSchema.validated(settings, kinds: importableKinds, numberRules: importableNumberRules)
    }

    /// The keys of the current settings that applying `accepted` removes, sorted.
    ///
    /// A settings file replaces every setting, so it removes the keys it lacks.
    ///
    /// - Parameters:
    ///   - accepted: The validated settings that are applied.
    ///   - current: The current settings.
    static func keysRemoved(applying accepted: [String: Any], over current: [String: Any]) -> [String] {
        current.keys.filter { accepted[$0] == nil }.sorted()
    }
}
