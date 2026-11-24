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
        /// Whether a Command-drag of an app's item across the holzBar icon sets the app's section
        /// (macOS 27; on by default).
        case commandDragSetsSection = "CommandDragSetsSection"
        /// Whether holzBar draws a stand-in icon for a visible app whose icon macOS 27 hides
        /// anyway (on by default).
        case standInIcons = "StandInIcons"
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
        /// macOS 27: what holzBar does when macOS folds menu bar items away because the bar is full.
        /// The raw values of `MakeRoomMode`: 0 Off, 1 Ask, 2 Automatic. Absent means Ask; new
        /// values are only appended.
        case makeRoomMode = "MakeRoomMode"
        /// macOS 27: whether holzBar asks where a new menu bar app goes, once per app. Off by default.
        case asksWhereNewAppGoes = "AsksWhereNewAppGoes"
        case keepLiveActivitiesVisible = "KeepLiveActivitiesVisible"
        case autoZenWhileSharingScreen = "AutoZenWhileSharingScreen"
        case openHiddenItemsInMenuBar = "OpenHiddenItemsInMenuBar"
        /// The identity keys of the items shown for a moment when they change.
        case revealOnChangeItems = "RevealOnChangeItems"
        /// The image each item shows, by identity: "app" or "file:<name>.png".
        case itemIcons = "ItemIcons"
        case layoutProfiles = "LayoutProfiles"
        case currentLayoutProfile = "CurrentLayoutProfile"
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
        /// Whether the onboarding waits to be shown: set at the first launch of a new install,
        /// cleared when it opens. Local to the Mac.
        case onboardingPending = "OnboardingPending"
        /// The core version of holzBar the What's New window last covered (`1.0.1` for
        /// `1.0.1-beta1`), as text. It describes this Mac's install, so it stays here: never
        /// exported, imported or synced.
        case lastSeenVersion = "WhatsNewLastSeenVersion"
        /// Whether the What's New window opens by itself after an update (a boolean, on by
        /// default). Exported and imported like the other choices.
        case whatsNewShowsAfterUpdate = "WhatsNewShowsAfterUpdate"
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
        /// The bundle identifiers of new menu bar apps whose question is not answered yet (a list
        /// of strings, at most 512), kept so a quit does not lose a question. They name the apps the
        /// user runs, so this stays on this Mac: never exported or imported.
        case newAppQuestionPending = "NewAppQuestionPending"
        /// The bundle identifiers the user asked never to be asked about again, with "Don't ask
        /// again" (a list of strings, at most 512). They name the apps the user runs, so this
        /// stays on this Mac: never exported or imported.
        case newAppQuestionDeclined = "NewAppQuestionDeclined"
        /// The section of each item before macOS 27, keyed by its identity (`ItemIdentity`):
        /// 0 visible, 1 hidden, 2 always hidden.
        case itemSections = "ItemSections"
        /// The order of the items before macOS 27, left to right across the bar, as identity keys
        /// (`ItemOrder`), saved with the sections. A new key: no migration, and it is exported
        /// and imported like ``itemSections``.
        case itemOrder = "ItemOrder"
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
        /// Whether the island opens, resizes, closes and widens with springs that overshoot (a
        /// boolean, on by default); off, it takes a plain 0.3 s ease. Reduce Motion still wins.
        case notchHubBounces = "NotchHubBounces"
        /// Whether a scroll on the closed notch opens and closes the Notch hub and a sideways swipe
        /// skips a track (a boolean, off by default). The scroll monitor exists only while it is on.
        case notchHubGestures = "NotchHubGestures"
        /// Whether the Notch hub opens on what is active (a meeting soon, a live activity, music)
        /// instead of the module last chosen (a boolean, on by default).
        case notchHubShowsActiveFirst = "NotchHubShowsActiveFirst"
        /// The displays the Notch hub opens on, as the raw value of `NotchHubDisplays`.
        case notchHubDisplays = "NotchHubDisplays"
        /// The display cutout the Notch hub assumes instead of the detected one, as the raw value
        /// of `DisplayCutoutOverride` (0 to 3). Local to this Mac, because it describes this Mac's
        /// display: never exported or imported.
        case notchHubCutout = "NotchHubCutout"
        /// The tab the Notch hub showed last. Local to the Mac: never exported or imported.
        case notchHubLastTab = "NotchHubLastTab"
        /// The timers of the Notch hub's Timers module, as JSON (`TimerBoard`). Local to this
        /// Mac: never exported, imported or synced.
        case timersBoard = "TimersBoard"
        /// The sound that rings when a timer ends, as the raw value of `TimerFinishSound`.
        case timersFinishSound = "TimersFinishSound"
        /// The players the Now Playing module follows, as the raw value of `NowPlayingPlayers`
        /// (1 Music, 2 Spotify, 3 both).
        case nowPlayingPlayers = "NowPlayingPlayers"
        /// Whether the Now Playing module also reads what every other app plays, through a
        /// private macOS interface and a helper (a boolean, off by default). It turns a private
        /// interface on, so it never travels: local to this Mac, never exported, imported or
        /// synced.
        case nowPlayingReadsAllApps = "NowPlayingReadsAllApps"
        /// Whether the Calendar module shows all-day events (a boolean, on by default).
        case calendarShowsAllDay = "CalendarShowsAllDay"
        /// The identifiers of the calendars the user switched off in the Calendar module. They
        /// name the user's accounts, so this stays on this Mac: never exported or imported.
        case calendarHiddenCalendars = "CalendarHiddenCalendars"
        /// How many minutes before a meeting the closed notch counts down to it (a whole number,
        /// 0 Off, 1, 5, 10 or 15; the raw values of `CountdownLead`, new ones only appended; 5 by
        /// default).
        case calendarCountdownLead = "CalendarCountdownLead"
        /// Whether the Live activities module shows a camera or the microphone in use by another
        /// app (a boolean, on by default).
        case liveActivitiesCapture = "LiveActivitiesCapture"
        /// Whether the Live activities module watches the Downloads folder for downloads in
        /// progress (a boolean, off by default). Switching it on is when macOS asks for the folder.
        case liveActivitiesDownloads = "LiveActivitiesDownloads"
        /// Whether the Notch hub opens on the File drop tab when a file is dragged to the notch
        /// (a boolean, on by default).
        case fileDropOpensOnDrag = "FileDropOpensOnDrag"
        /// Whether a file leaves the File drop stash once it was dropped elsewhere (a boolean,
        /// on by default).
        case fileDropRemovesAfterDrop = "FileDropRemovesAfterDrop"

        // MARK: Accessory Alerts
        /// Whether the Accessory alerts module widens the notch for an alert when an accessory
        /// connects (a boolean, on by default).
        case accessoryAlertsOnConnect = "AccessoryAlertsOnConnect"
        /// Whether the Accessory alerts module widens the notch for an alert when an accessory
        /// disconnects (a boolean, off by default: AirPods in their case disconnect often).
        case accessoryAlertsOnDisconnect = "AccessoryAlertsOnDisconnect"
        /// Whether the Accessory alerts module widens the notch for an alert when an accessory's
        /// battery is low (a boolean, on by default).
        case accessoryAlertsOnLowBattery = "AccessoryAlertsOnLowBattery"
        /// The level, in percent, at or below which an accessory's battery is low (a number
        /// from 10 to 30, 20 by default).
        case accessoryAlertsLowBatteryLevel = "AccessoryAlertsLowBatteryLevel"
        /// Whether the Accessory alerts module reads accessory battery levels, which uses one
        /// macOS call that Apple does not document (a boolean, on by default; the switch that
        /// turns that call off).
        case accessoryAlertsReadsBattery = "AccessoryAlertsReadsBattery"

        // MARK: Notifications
        /// The names of the apps whose notifications the Notifications module never shows (a
        /// list of strings). They name the apps the user runs, so this stays on this Mac:
        /// never exported or imported.
        case notificationsExcludedApps = "NotificationsExcludedApps"
        /// How long a new notification shows as a count in the closed notch, in seconds (a whole
        /// number from 3 to 30; the model snaps it to 3, 5, 10, 15 or 30, 5 by default).
        case notificationsDisplayTime = "NotificationsDisplayTime"

        // MARK: Display Controls
        /// Whether the Display controls module shows brightness sliders, which use a private
        /// macOS interface (a boolean, on by default; the switch that turns that part off).
        case displayControlsBrightness = "DisplayControlsBrightness"
        /// Whether the Display controls module reads and sets external monitors over DDC/CI,
        /// which uses a private macOS interface (a boolean, off by default; the switch of that
        /// part, stored on this Mac only).
        case displayControlsExternalMonitors = "DisplayControlsExternalMonitors"
        /// How far software dimming darkens each external display: a dictionary of display UUID
        /// to a level above 0 and up to 0.9 (D-19). The identifiers are those of this Mac's
        /// displays, so it stays on this Mac only: never exported or imported.
        case displayControlsDimLevels = "DisplayControlsDimLevels"

        // MARK: System readouts
        /// How the network speed counts: the raw value of `ReadoutRateUnit` (a whole number, 0
        /// for bytes per second and 1 for bits per second). It is exported with the settings
        /// and works while the System readouts module is off, because the Network Speed widget
        /// follows it too.
        case readoutsRateUnit = "ReadoutsRateUnit"
        /// The tiles of System readouts the user left on, and "thermal" for the thermal state
        /// line under the CPU tile (a list of strings, each a known id). Absent means every tile
        /// is on. It is exported with the settings; an imported list keeps only known ids.
        case readoutTiles = "ReadoutTiles"
        /// How often the System readouts tiles read CPU, GPU, memory and network while the hub is
        /// open, in seconds (a whole number from 2 to 30, 2 by default). It is exported with the
        /// settings.
        case readoutsTileRefresh = "ReadoutsTileRefresh"
        /// Whether System readouts reads the load of the graphics processor, which uses a private
        /// macOS interface (a boolean, off by default; the switch of that part, stored on this
        /// Mac only).
        case readoutsReadsGPU = "ReadoutsReadsGPU"

        // MARK: Dock badges
        /// The bundle identifiers of the apps whose Dock badge shows in the menu bar, in the order
        /// chosen (a list of strings, at most 64). It is exported with the settings; an imported
        /// list keeps only valid, unique bundle identifiers.
        case dockBadgeApps = "DockBadgeApps"
        /// Whether Dock badges reads the badge on the Dock icons of the chosen apps, which uses a
        /// private macOS interface (a boolean, off by default; the switch of that part, stored on
        /// this Mac only).
        case dockBadgesReadsCounts = "DockBadgesReadsCounts"

        // MARK: System alerts
        // Every System alerts value but the System notifications switch is exported with the
        // settings. An imported number outside its whole-number range is refused, and the model
        // brings every stored value through
        // `ThresholdRule.validatedLimit` and `AlertHold.snapped` again, because the defaults can
        // hold anything. The five holds are seconds (a whole number from 0 to 900) and are
        // snapped to the nearest preset: 0, 10, 30, 60, 300 or 900.
        /// Whether the CPU load rule is on (a boolean, on by default).
        case systemAlertsCPU = "SystemAlertsCPU"
        /// The CPU load, in percent, above which the rule fires (a whole number from 50 to 95,
        /// in steps of 5, 90 by default).
        case systemAlertsCPUThreshold = "SystemAlertsCPUThreshold"
        /// How long the CPU load has to hold, in seconds (a whole number from 0 to 900, 300 by
        /// default).
        case systemAlertsCPUHold = "SystemAlertsCPUHold"
        /// Whether the memory pressure rule is on (a boolean, off by default).
        case systemAlertsMemoryPressure = "SystemAlertsMemoryPressure"
        /// The memory pressure level that fires the rule (a whole number: 1 is Warning and 2 is
        /// Critical, the same set as `ThresholdRule.memoryLevels`; 1 by default).
        case systemAlertsMemoryPressureLevel = "SystemAlertsMemoryPressureLevel"
        /// How long the memory pressure has to hold, in seconds (a whole number from 0 to 900,
        /// 60 by default).
        case systemAlertsMemoryPressureHold = "SystemAlertsMemoryPressureHold"
        /// Whether the thermal state rule is on (a boolean, on by default).
        case systemAlertsThermal = "SystemAlertsThermal"
        /// The thermal state that fires the rule (a whole number: 1 is Fair, 2 is Serious and 3
        /// is Critical, the same set as `ThresholdRule.thermalLevels`; 2 by default).
        case systemAlertsThermalLevel = "SystemAlertsThermalLevel"
        /// How long the thermal state has to hold, in seconds (a whole number from 0 to 900, 0
        /// by default).
        case systemAlertsThermalHold = "SystemAlertsThermalHold"
        /// Whether the free disk space rule is on (a boolean, on by default).
        case systemAlertsFreeDisk = "SystemAlertsFreeDisk"
        /// The free space, in decimal gigabytes, below which the rule fires (a whole number from
        /// 5 to 200 that the model snaps to 5, 10, 20, 50, 100 or 200; 10 by default).
        case systemAlertsFreeDiskThreshold = "SystemAlertsFreeDiskThreshold"
        /// How long the free space has to stay low, in seconds (a whole number from 0 to 900, 60
        /// by default).
        case systemAlertsFreeDiskHold = "SystemAlertsFreeDiskHold"
        /// Whether the Mac battery rule is on (a boolean, on by default; it applies on battery
        /// power only).
        case systemAlertsMacBattery = "SystemAlertsMacBattery"
        /// The charge, in percent, below which the rule fires (a whole number from 5 to 50, in
        /// steps of 5, 20 by default).
        case systemAlertsMacBatteryThreshold = "SystemAlertsMacBatteryThreshold"
        /// How long the charge has to stay low, in seconds (a whole number from 0 to 900, 0 by
        /// default).
        case systemAlertsMacBatteryHold = "SystemAlertsMacBatteryHold"
        /// Whether an alert also arrives as a system notification (a boolean, off by default; a
        /// per-Mac permission state, stored on this Mac only and never exported or imported).
        case systemAlertsNotifications = "SystemAlertsNotifications"

        // MARK: Indicators
        /// Whether a change of the keyboard input source flashes in the closed notch (a boolean, off
        /// by default). It starts the system's input source notifications only while it is on.
        case indicatorsInputSource = "IndicatorsInputSource"
        /// How long the input source flash stays, in seconds (a number from 0.5 to 3; the model snaps
        /// it to 0.5, 1, 1.5, 2 or 3, 1.5 by default).
        case indicatorsInputSourceDuration = "IndicatorsInputSourceDuration"
        /// Whether a change of the volume (and, for the keys holzBar takes, of the brightness) shows
        /// in the closed notch (a boolean, off by default). It starts the volume listener only while
        /// it is on.
        case indicatorsVolumeBrightness = "IndicatorsVolumeBrightness"
        /// Whether holzBar takes the volume and brightness keys it can handle and shows its own
        /// display instead of the system's (a boolean, off by default; a private-interface switch,
        /// stored on this Mac only and never exported or imported). Turning it on asks for
        /// Accessibility, and a session event tap exists only while it is on and trusted.
        case indicatorsReplacesSystemDisplay = "IndicatorsReplacesSystemDisplay"

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
        /// Runs the macOS 27 click bridge's tap on the main run loop instead of its own thread,
        /// for a Mac where the thread misbehaves. Hidden:
        /// `defaults write com.holzcloud.holzBar MacOS27ClickBridgeOnMainThread -bool true`.
        /// Never exported or imported.
        case macOS27ClickBridgeOnMainThread = "MacOS27ClickBridgeOnMainThread"

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
        /// Set by an import from another app once the record of the earlier settings is on disk,
        /// and cleared by the launch that offers its undo, so the offer shows once. Stored on this
        /// Mac only: never exported or imported.
        case previousAppImportUndoPending = "PreviousAppImportUndoPending"

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
            .commandDragSetsSection,
            .standInIcons,
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
            .onboardingPending,
            .whatsNewShowsAfterUpdate,
            .screenRecordingOffered,
            .systemItemsMayHide,
            .lockHiddenItems,
            .usageSuggestionsEnabled,
            .smartCategories,
            .enableSecondaryContextMenu,
            .keepLiveActivitiesVisible,
            .asksWhereNewAppGoes,
            .autoZenWhileSharingScreen,
            .notchHubOpensOnHover,
            .notchHubGestures,
            .notchHubBounces,
            .notchHubShowsActiveFirst,
            .calendarShowsAllDay,
            .nowPlayingReadsAllApps,
            .liveActivitiesCapture,
            .liveActivitiesDownloads,
            .fileDropOpensOnDrag,
            .fileDropRemovesAfterDrop,
            .accessoryAlertsOnConnect,
            .accessoryAlertsOnDisconnect,
            .accessoryAlertsOnLowBattery,
            .accessoryAlertsReadsBattery,
            .displayControlsBrightness,
            .displayControlsExternalMonitors,
            .readoutsReadsGPU,
            .dockBadgesReadsCounts,
            .systemAlertsCPU,
            .systemAlertsMemoryPressure,
            .systemAlertsThermal,
            .systemAlertsFreeDisk,
            .systemAlertsMacBattery,
            .systemAlertsNotifications,
            .indicatorsInputSource,
            .indicatorsVolumeBrightness,
            .indicatorsReplacesSystemDisplay,
            .openHiddenItemsInMenuBar,
            .macOS27LayoutSeeded,
            .macOS27ShelfWaitsForRefresh,
            .debugDropsBarrierExitEvent,
            .debugHangsItemImageCapture,
            .macOS27ClickBridgeOnMainThread,
            .hasMigrated0_8_0,
            .hasMigrated0_10_0,
            .hasMigrated0_10_1,
            .hasMigrated0_11_10,
            .hasMigrated0_11_13,
            .hasMigrated0_11_13_1,
            .hasImportedPreviousSettings,
            .previousAppImportUndoPending,
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
            .notchHubCutout,
            .timersFinishSound,
            .nowPlayingPlayers,
            .rehideStrategy,
            .rehideInterval,
            .itemSpacingOffset,
            .sectionDividerStyle,
            .showOnHoverDelay,
            .tempShowInterval,
            .newItemsPlacement,
            .makeRoomMode,
            .spacerCount,
            .spacerWidth,
            .layoutSnapshotsLimit,
            .macOS27ClickRestoreDelay,
            .lastRunMacOSMajor,
            .accessoryAlertsLowBatteryLevel,
            .readoutsRateUnit,
            .readoutsTileRefresh,
            .systemAlertsCPUThreshold,
            .systemAlertsCPUHold,
            .systemAlertsMemoryPressureLevel,
            .systemAlertsMemoryPressureHold,
            .systemAlertsThermalLevel,
            .systemAlertsThermalHold,
            .systemAlertsFreeDiskThreshold,
            .systemAlertsFreeDiskHold,
            .systemAlertsMacBatteryThreshold,
            .systemAlertsMacBatteryHold,
            .indicatorsInputSourceDuration,
            .notificationsDisplayTime,
            .calendarCountdownLead,
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
            .lastSeenVersion,
            .notchHubLastTab:
            .string
        case .knownItemTags,
            .itemOrder,
            .knownApplications27,
            .newAppQuestionPending,
            .newAppQuestionDeclined,
            .hiddenSystemItems27,
            .titleChangingItemOwners,
            .revealOnChangeItems,
            .calendarHiddenCalendars,
            .notificationsExcludedApps,
            .readoutTiles,
            .dockBadgeApps:
            .stringArray
        case .hotkeys,
            .revealRules,
            .macOS27Layout,
            .displayBehaviors,
            .displayControlsDimLevels,
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
        case .accessoryAlertsLowBatteryLevel:
            .clamped(10...30)
        case .indicatorsInputSourceDuration:
            // Seconds; the model snaps them to the choices of IndicatorLook.
            .clamped(0.5...3)
        case .spacerCount:
            .wholeNumber(0...10)
        // The raw values of NotchHubDisplays (0 to 3); new ones are only appended.
        case .notchHubDisplays:
            .wholeNumber(0...3)
        case .notchHubCutout:
            .wholeNumber(0...3)
        case .timersFinishSound:
            .wholeNumber(0...5)
        case .nowPlayingPlayers:
            .wholeNumber(1...3)
        case .readoutsRateUnit:
            .wholeNumber(0...1)
        case .readoutsTileRefresh:
            .wholeNumber(2...30)
        case .systemAlertsCPUThreshold:
            .wholeNumber(50...95)
        case .systemAlertsMemoryPressureLevel:
            // Exactly ThresholdRule.memoryLevels: 1 Warning, 2 Critical.
            .wholeNumber(1...2)
        case .systemAlertsThermalLevel:
            // Exactly ThresholdRule.thermalLevels: 1 Fair, 2 Serious, 3 Critical.
            .wholeNumber(1...3)
        case .systemAlertsFreeDiskThreshold:
            .wholeNumber(5...200)
        case .systemAlertsMacBatteryThreshold:
            .wholeNumber(5...50)
        case .systemAlertsCPUHold,
            .systemAlertsMemoryPressureHold,
            .systemAlertsThermalHold,
            .systemAlertsFreeDiskHold,
            .systemAlertsMacBatteryHold:
            // Seconds; the model snaps them to AlertHold's presets.
            .wholeNumber(0...900)
        case .notificationsDisplayTime:
            // Seconds; the model snaps them to the choices of NotificationQueue.
            .wholeNumber(3...30)
        case .calendarCountdownLead:
            // Minutes; exactly the raw values of CountdownLead, which the model snaps.
            .wholeNumber(0...15)
        case .makeRoomMode:
            // Exactly the raw values of MakeRoomMode (0 Off, 1 Ask, 2 Automatic); new ones are only appended.
            .wholeNumber(0...2)
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
    /// The debug defaults stay on this Mac, and so do the names of the
    /// Shortcuts the widget buttons run (D-25), the sections that item rules remember, the
    /// tab the Notch hub showed last, the timers (they hold the user's labels), the calendars
    /// the user switched off (their identifiers name the user's accounts), the version the
    /// What's New window last covered (it describes this install), whether the
    /// Shelf's fold was left open and what each display does with the hidden items (the
    /// displays' identifiers are those of this Mac), how far software dimming darkens each display
    /// (also keyed by display), and the two switches that turn a private
    /// interface on: Now Playing's Read all apps, Display controls' External monitors, System
    /// readouts' Read GPU load and Dock badges' Read badge counts, Indicators' Replace the system display, the System alerts' System notifications switch (a per-Mac
    /// permission state) and the display cutout, which describes this Mac's hardware. The bundle
    /// identifiers of the new menu bar apps whose question waits (and, with them, of those the
    /// user asked never to be asked about) name the apps the user runs and stay here too. So does the marker that offers the undo
    /// of an import once, which describes this launch only.
    static let localOnlyKeys: Set<Defaults.Key> = [
        .lastRunMacOSMajor,
        .lockHiddenItems,
        .usageSuggestionsEnabled,
        .cleanUpOffered,
        .onboardingPending,
        .lastSeenVersion,
        .screenRecordingOffered,
        .widgetShortcutNames,
        .itemRuleShownSections,
        .notchHubLastTab,
        .timersBoard,
        .calendarHiddenCalendars,
        .nowPlayingReadsAllApps,
        .displayControlsExternalMonitors,
        .displayControlsDimLevels,
        .readoutsReadsGPU,
        .dockBadgesReadsCounts,
        .indicatorsReplacesSystemDisplay,
        .systemAlertsNotifications,
        .notchHubCutout,
        .notificationsExcludedApps,
        .newAppQuestionPending,
        .newAppQuestionDeclined,
        .shelfAlwaysHiddenFoldOpen,
        .displayBehaviors,
        .debugDropsBarrierExitEvent,
        .debugHangsItemImageCapture,
        .macOS27ClickBridgeOnMainThread,
        .previousAppImportUndoPending,
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
        // A file never brings a tile id this build does not know, a repeated one, or more than
        // `ReadoutTileChoice.maximumChecked` entries looked at: the list is sanitized.
        let tilesKey = Self.readoutTiles.rawValue
        if let tiles = result.accepted[tilesKey] as? [String] {
            result.accepted[tilesKey] = ReadoutTileChoice.sanitized(tiles)
        }
        // A file never brings an app that is not a bundle identifier, a repeated one, or more
        // than `DockBadgeApps.maximumCount`: the list is sanitized.
        let dockAppsKey = Self.dockBadgeApps.rawValue
        if let apps = result.accepted[dockAppsKey] as? [String] {
            result.accepted[dockAppsKey] = DockBadgeApps.sanitized(apps)
        }
        // A file never brings a stored order of more keys than `ItemOrder` keeps, or an empty,
        // overlong or repeated key: the order is read on the main thread at every restore.
        let orderKey = Self.itemOrder.rawValue
        if let order = result.accepted[orderKey] as? [String] {
            result.accepted[orderKey] = ItemOrder.sanitized(order)
        }
        // A file never brings more profiles or entries than the limits of `LayoutProfileList`, a
        // name that is empty, white space or over its byte cap, or a section that does not exist:
        // the list is decoded, validated and encoded again, and a repeated name gets a number.
        let profilesKey = Self.layoutProfiles.rawValue
        if let data = result.accepted[profilesKey] as? Data {
            if let normalized = LayoutProfileList.normalized(data) {
                result.accepted[profilesKey] = normalized
            } else {
                result.accepted.removeValue(forKey: profilesKey)
                result.ignored = (result.ignored + [profilesKey]).sorted()
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
