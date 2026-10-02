//
//  Defaults.swift
//  holzBar
//

import Foundation

enum Defaults {
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

extension Defaults {
    /// The keys holzBar stores its settings under.
    ///
    /// Every key declares the kind of value it holds (``settingsKind``), so an imported
    /// or synced settings file can only set holzBar's own keys, with values of the
    /// expected kind (``SettingsSchema``).
    enum Key: String, CaseIterable {
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

        // MARK: Hotkeys Settings
        case hotkeys = "Hotkeys"

        // MARK: Advanced Settings
        case enableAlwaysHiddenSection = "EnableAlwaysHiddenSection"
        case showAllSectionsOnUserDrag = "ShowAllSectionsOnUserDrag"
        case sectionDividerStyle = "SectionDividerStyle"
        case hideApplicationMenus = "HideApplicationMenus"
        case enableSecondaryContextMenu = "EnableSecondaryContextMenu"
        case showOnHoverDelay = "ShowOnHoverDelay"
        case tempShowInterval = "TempShowInterval"
        case newItemsPlacement = "NewItemsPlacement"
        case keepLiveActivitiesVisible = "KeepLiveActivitiesVisible"
        case layoutProfiles = "LayoutProfiles"
        case currentLayoutProfile = "CurrentLayoutProfile"
        case syncsSettingsWithICloud = "SyncsSettingsWithICloud"
        case itemGroups = "ItemGroups"
        case spacerCount = "SpacerCount"
        case spacerWidth = "SpacerWidth"
        case revealRules = "RevealRules"
        case knownItemTags = "KnownItemTags"
        case knownApplications27 = "KnownApplications27"

        // MARK: Appearance Settings
        case menuBarAppearanceConfigurationV2 = "MenuBarAppearanceConfigurationV2"

        // MARK: macOS 27
        case macOS27Layout = "MacOS27Layout"
        case macOS27LayoutSeeded = "MacOS27LayoutSeeded"
        case macOS27ClickRestoreDelay = "MacOS27ClickRestoreDelay"
        case macOS27ShelfWaitsForRefresh = "MacOS27IceBarWaitsForRefresh"

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

extension Defaults.Key {
    /// The kind of value stored under this key.
    ///
    /// The switch has no `default`, so a new key must declare its kind before it
    /// can be built; imported and synced settings are checked against these kinds.
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
            .enableAlwaysHiddenSection,
            .showAllSectionsOnUserDrag,
            .hideApplicationMenus,
            .enableSecondaryContextMenu,
            .keepLiveActivitiesVisible,
            .syncsSettingsWithICloud,
            .macOS27LayoutSeeded,
            .macOS27ShelfWaitsForRefresh,
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
            .knownApplications27:
            .stringArray
        case .hotkeys,
            .revealRules,
            .macOS27Layout:
            // Their readers cast the contents themselves, so the kind is checked
            // only at the top level.
            .dictionary
        }
    }

    /// The stored key names an imported or synced settings file may set, with the
    /// kind of value each one takes.
    static let importableKinds: [String: SettingsSchema.Kind] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0.rawValue, $0.settingsKind) }
    )
}
