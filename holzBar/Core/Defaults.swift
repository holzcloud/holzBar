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
        /// Whether the holzBar Shelf fades in when it opens. Earlier versions wrote it; it is read
        /// only to choose the animation style of a user who never chose one
        /// (`RevealAnimationStyle.migrated`).
        case animatesShelf = "AnimatesShelf"
        /// Whether showing and hiding the sections slides the menu bar's items. Earlier versions
        /// wrote it; it is read only to choose the animation style of a user who never chose one.
        case animatesShowHide = "AnimatesShowHide"
        /// How showing and hiding looks: instant, smooth or fade (`RevealAnimationStyle`). Never
        /// with Reduce Motion on. A new key, so it takes no old name.
        case revealAnimationStyle = "RevealAnimationStyle"
        /// Whether a click on the clock opens Notification Center while items are hidden (macOS
        /// 27; on by default).
        case clockOpensNotificationCenter = "ClockOpensNotificationCenter"
        /// Whether a change in the Menu Bar Layout pane moves the item at once (off by default:
        /// the pane draws a draft, and Apply lays the bar out).
        case appliesLayoutChangesImmediately = "AppliesLayoutChangesImmediately"
        /// What each display does with the hidden items, by display UUID (`DisplayBehaviors`).
        /// Stays on this Mac.
        case displayBehaviors = "DisplayBehaviors"
        /// How the holzBar Shelf arranges its items: in a row, a grid or a column.
        case shelfLayout = "ShelfLayout"
        case shelfLocation = "IceBarLocation"
        /// Whether the holzBar Shelf hangs from the menu bar or floats a little below it. A new
        /// key, so it takes no old name.
        case shelfStyle = "ShelfStyle"
        case shelfDisplays = "IceBarDisplays"
        case showsNotchOverflowInShelf = "ShowsNotchOverflowInIceBar"
        /// Whether typing in the holzBar Shelf finds an item (on by default). A new key, so it
        /// takes no old name.
        case shelfFindsByTyping = "ShelfFindsByTyping"
        /// Whether the holzBar Shelf opens the fold of the always-hidden items folded each time or
        /// as the user left it (`ShelfAlwaysHiddenFold`).
        case shelfAlwaysHiddenFold = "ShelfAlwaysHiddenFold"
        /// Whether the user left the fold of the always-hidden items open; stays on this Mac.
        case shelfAlwaysHiddenFoldOpen = "ShelfAlwaysHiddenFoldOpen"
        /// Whether the holzBar Shelf also lists the applications that are not running, dimmed
        /// (off by default).
        case shelfShowsClosedApps = "ShelfShowsClosedApps"
        /// Whether a tile of the holzBar Shelf can be dragged to arrange the items (on by default).
        case shelfDragsTiles = "ShelfDragsTiles"
        case showOnClick = "ShowOnClick"
        case showOnHover = "ShowOnHover"
        case showOnScroll = "ShowOnScroll"
        case autoRehide = "AutoRehide"
        case rehideStrategy = "RehideStrategy"
        case rehideInterval = "RehideInterval"
        case itemSpacingOffset = "ItemSpacingOffset"
        /// macOS 27: a dot on holzBar's icon while another app uses the microphone or a camera.
        case holzBarIconShowsCaptureDot = "HolzBarIconShowsCaptureDot"
        /// Whether holzBar's icon carries the number of hidden items while they are hidden (off by default).
        case showsHiddenItemCount = "ShowsHiddenItemCount"

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
        /// The widgets of the menu bar, as JSON (`WidgetDefinition`): kind, source, format and
        /// order. Exported and imported as one unit (D-25, D-26).
        case widgets = "Widgets"
        /// The name of each button widget's Shortcut, by widget identifier. Local to the Mac:
        /// never exported, imported or synced (D-25).
        case widgetShortcutNames = "WidgetShortcutNames"
        case spacerCount = "SpacerCount"
        case spacerWidth = "SpacerWidth"
        case revealRules = "RevealRules"
        /// Whether the clean-up assistant was offered once, at the first launch.
        case cleanUpOffered = "CleanUpOffered"
        /// Whether the holzBar Shelf asked once whether it may use Screen Recording; the answer is
        /// kept, so it never asks again. Local to the Mac.
        case screenRecordingOffered = "ScreenRecordingOffered"
        /// Whether the pinned system items may be moved into hidden sections (they may not by default).
        case systemItemsMayHide = "SystemItemsMayHide"
        /// Whether showing the hidden items asks for Touch ID or the password. Local to the
        /// Mac: never exported, imported or synced.
        case lockHiddenItems = "LockHiddenItems"
        /// Whether the history of the layout is turned off (it is on by default).
        case layoutSnapshotsDisabled = "LayoutSnapshotsDisabled"
        /// How many snapshots of the layout are kept, not counting starred ones.
        case layoutSnapshotsLimit = "LayoutSnapshotsLimit"
        /// Whether the usage suggestions count how often items are opened. Local to the Mac:
        /// never exported, imported or synced.
        case usageSuggestionsEnabled = "UsageSuggestionsEnabled"
        /// Whether the search offers category chips (on by default). A new key, so it takes no
        /// old name. It is exported and imported like the other choices.
        case smartCategories = "SmartCategories"
        /// The saved looks of the menu bar (moods), as JSON.
        case appearanceMoods = "AppearanceMoods"
        /// The automation rules, as JSON (`AutomationRule`).
        case automationRules = "AutomationRules"
        /// The section each item that a rule controls has while the rule shows it, by identity
        /// key: 0 visible, 1 hidden. Local to the Mac: never exported, imported or synced.
        case itemRuleShownSections = "ItemRuleShownSections"
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
        /// The major macOS version holzBar last ran on; an upgrade path starts when it differs.
        case lastRunMacOSMajor = "LastRunMacOSMajor"
        case macOS27ClickRestoreDelay = "MacOS27ClickRestoreDelay"
        case macOS27ShelfWaitsForRefresh = "MacOS27IceBarWaitsForRefresh"
        /// The system items the user hid on macOS 27, by name (`SystemItem27`).
        case hiddenSystemItems27 = "HiddenSystemItems27"
        /// The replacement items of the Apple Items module, as JSON (`AppleItemReplacement`).
        case appleItemReplacements = "AppleItemReplacements"

        // MARK: Notch hub
        /// Whether resting the pointer at the notch opens the Notch hub (a boolean, on by default).
        case notchHubOpensOnHover = "NotchHubOpensOnHover"
        /// The displays the Notch hub opens on, as the raw value of `NotchHubDisplays`.
        case notchHubDisplays = "NotchHubDisplays"
        /// The tab the Notch hub showed last. Local to the Mac: never exported or imported.
        case notchHubLastTab = "NotchHubLastTab"
        /// The timers of the Notch hub's Timers module, as JSON (`TimerBoard`). Local to this
        /// Mac: never exported, imported or synced.
        case timersBoard = "TimersBoard"
        /// The sound that rings when a timer ends, as the raw value of `TimerFinishSound`.
        case timersFinishSound = "TimersFinishSound"
        /// Whether the Calendar module shows all-day events (a boolean, on by default).
        case calendarShowsAllDay = "CalendarShowsAllDay"
        /// The identifiers of the calendars the user switched off in the Calendar module. They
        /// name the user's accounts, so this stays on this Mac: never exported or imported.
        case calendarHiddenCalendars = "CalendarHiddenCalendars"
        /// Whether the Live activities module shows a camera or the microphone in use by another
        /// app (a boolean, on by default).
        case liveActivitiesCapture = "LiveActivitiesCapture"
        /// Whether the Live activities module watches the Downloads folder for downloads in
        /// progress (a boolean, off by default). Switching it on is when macOS asks for the folder.
        case liveActivitiesDownloads = "LiveActivitiesDownloads"

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
            .animatesShelf,
            .animatesShowHide,
            .clockOpensNotificationCenter,
            .appliesLayoutChangesImmediately,
            .showsNotchOverflowInShelf,
            .shelfFindsByTyping,
            .shelfAlwaysHiddenFoldOpen,
            .shelfShowsClosedApps,
            .shelfDragsTiles,
            .showOnClick,
            .showOnHover,
            .showOnScroll,
            .autoRehide,
            .holzBarIconShowsCaptureDot,
            .showsHiddenItemCount,
            .enableAlwaysHiddenSection,
            .showAllSectionsOnUserDrag,
            .hideApplicationMenus,
            .keepsDockIconHidden,
            .layoutSnapshotsDisabled,
            .cleanUpOffered,
            .screenRecordingOffered,
            .systemItemsMayHide,
            .lockHiddenItems,
            .usageSuggestionsEnabled,
            .smartCategories,
            .enableSecondaryContextMenu,
            .keepLiveActivitiesVisible,
            .autoZenWhileSharingScreen,
            .notchHubOpensOnHover,
            .calendarShowsAllDay,
            .liveActivitiesCapture,
            .liveActivitiesDownloads,
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
            .shelfStyle,
            .shelfLayout,
            .shelfDisplays,
            .shelfAlwaysHiddenFold,
            .revealAnimationStyle,
            .notchHubDisplays,
            .timersFinishSound,
            .rehideStrategy,
            .rehideInterval,
            .itemSpacingOffset,
            .sectionDividerStyle,
            .showOnHoverDelay,
            .tempShowInterval,
            .newItemsPlacement,
            .spacerCount,
            .spacerWidth,
            .layoutSnapshotsLimit,
            .macOS27ClickRestoreDelay,
            .lastRunMacOSMajor,
            .menuBarBorderWidth,
            .menuBarTintKind:
            .number
        case .holzBarIcon,
            .layoutProfiles,
            .appearanceMoods,
            .automationRules,
            .itemGroups,
            .widgets,
            .appleItemReplacements,
            .timersBoard,
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
        case .currentLayoutProfile,
            .notchHubLastTab:
            .string
        case .knownItemTags,
            .knownApplications27,
            .hiddenSystemItems27,
            .titleChangingItemOwners,
            .revealOnChangeItems,
            .calendarHiddenCalendars:
            .stringArray
        case .hotkeys,
            .revealRules,
            .macOS27Layout,
            .displayBehaviors,
            .itemSections,
            .itemIcons,
            .widgetShortcutNames,
            .itemRuleShownSections:
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
        case .lastRunMacOSMajor:
            // A major macOS version; the key is never imported, the rule only completes the schema.
            .clamped(0...1000)
        case .menuBarBorderWidth:
            .clamped(1...3)
        case .spacerCount:
            .wholeNumber(0...10)
        case .notchHubDisplays:
            .wholeNumber(0...2)
        case .timersFinishSound:
            .wholeNumber(0...5)
        case .layoutSnapshotsLimit:
            .wholeNumber(1...100)
        case .shelfLocation,
            .shelfStyle,
            .shelfLayout,
            .shelfDisplays,
            .shelfAlwaysHiddenFold,
            .revealAnimationStyle,
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
    /// never sets it. The debug defaults stay on this Mac as well, and so do the names of the
    /// Shortcuts the widget buttons run (D-25), the sections that item rules remember, the
    /// tab the Notch hub showed last, the timers (they hold the user's labels), the calendars
    /// the user switched off (their identifiers name the user's accounts), whether the
    /// Shelf's fold was left open and what each display does with the hidden items (the
    /// displays' identifiers are those of this Mac).
    static let localOnlyKeys: Set<Defaults.Key> = [
        .syncsSettingsWithICloud,
        .lastRunMacOSMajor,
        .lockHiddenItems,
        .usageSuggestionsEnabled,
        .cleanUpOffered,
        .screenRecordingOffered,
        .widgetShortcutNames,
        .itemRuleShownSections,
        .notchHubLastTab,
        .timersBoard,
        .calendarHiddenCalendars,
        .shelfAlwaysHiddenFoldOpen,
        .displayBehaviors,
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
    ///
    /// - Parameters:
    ///   - settings: The settings read from outside the app.
    ///   - ownBundleIdentifier: holzBar's own bundle identifier (`Constants.bundleIdentifier`),
    ///     which the macOS 27 layout of a file never names (WR-01).
    static func validatedSettings(
        _ settings: [String: Any],
        ownBundleIdentifier: String
    ) -> (accepted: [String: Any], ignored: [String]) {
        var result = SettingsSchema.validated(settings, kinds: importableKinds, numberRules: importableNumberRules)
        // A file never brings a rule that runs or asks a script: scripts and their approvals
        // are local to the Mac.
        let rulesKey = Self.automationRules.rawValue
        if let data = result.accepted[rulesKey] as? Data {
            if let stripped = AutomationRule.removingScriptRules(from: data) {
                result.accepted[rulesKey] = stripped
            } else {
                result.accepted.removeValue(forKey: rulesKey)
                result.ignored = (result.ignored + [rulesKey]).sorted()
            }
        }
        // A file never brings more than six widgets, a kind or a source this build does not know,
        // or a field of its own (D-25, T-12-04): the list is decoded, validated and encoded again.
        let widgetsKey = Self.widgets.rawValue
        if let data = result.accepted[widgetsKey] as? Data {
            if let normalized = WidgetList.normalized(data) {
                result.accepted[widgetsKey] = normalized
            } else {
                result.accepted.removeValue(forKey: widgetsKey)
                result.ignored = (result.ignored + [widgetsKey]).sorted()
            }
        }
        // A file never brings a replacement item for anything but an Apple application, more than
        // six, or a symbol the app does not offer: the list is decoded, validated and encoded again.
        let replacementsKey = Self.appleItemReplacements.rawValue
        if let data = result.accepted[replacementsKey] as? Data {
            if let normalized = AppleItemReplacementList.normalized(data) {
                result.accepted[replacementsKey] = normalized
            } else {
                result.accepted.removeValue(forKey: replacementsKey)
                result.ignored = (result.ignored + [replacementsKey]).sorted()
            }
        }
        // A file never conceals holzBar itself: an entry for holzBar's own bundle in the macOS 27
        // layout would hide its icon and dividers. Widgets are keyed by their autosave names.
        let layoutKey = Self.macOS27Layout.rawValue
        if let layout = result.accepted[layoutKey] as? [String: Any] {
            result.accepted[layoutKey] = OwnBundle.removing(from: layout, bundleIdentifier: ownBundleIdentifier)
        }
        return result
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
