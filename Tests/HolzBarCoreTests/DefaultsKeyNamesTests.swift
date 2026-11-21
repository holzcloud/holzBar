import Foundation
import Testing
@testable import HolzBarCore

/// The stored names of every setting of release 1.0.5 (the commit tagged v1.0.5, 6ca506a1).
/// Renaming or removing one would lose a user's setting and break the import of Ice settings,
/// so a key may be added but never renamed or removed (decision D-13, SET-12). The only exceptions
/// are the keys in `retiredRawValues`: they held no setting any more and were removed on purpose.
@Suite("Defaults key names")
struct DefaultsKeyNamesTests {
    private static let releasedRawValues: [String] = [
        "AccessoryAlertsLowBatteryLevel",
        "AccessoryAlertsOnConnect",
        "AccessoryAlertsOnDisconnect",
        "AccessoryAlertsOnLowBattery",
        "AccessoryAlertsReadsBattery",
        "AnimatesShelf",
        "AnimatesShowHide",
        "AppearanceMoods",
        "AppleItemReplacements",
        "AppliesLayoutChangesImmediately",
        "AutoRehide",
        "AutoZenWhileSharingScreen",
        "AutomationRules",
        "CalendarHiddenCalendars",
        "CalendarShowsAllDay",
        "CanToggleAlwaysHiddenSection",
        "CleanUpOffered",
        "ClockOpensNotificationCenter",
        "CommandDragSetsSection",
        "CurrentLayoutProfile",
        "CustomIceIconIsTemplate",
        "DebugDropsBarrierExitEvent",
        "DebugHangsItemImageCapture",
        "DisplayBehaviors",
        "DisplayControlsBrightness",
        "EnableAlwaysHiddenSection",
        "EnableSecondaryContextMenu",
        "FileDropOpensOnDrag",
        "FileDropRemovesAfterDrop",
        "HasImportedIceSettings",
        "HiddenSystemItems27",
        "HideApplicationMenus",
        "HolzBarIconShowsCaptureDot",
        "Hotkeys",
        "IceBarDisplays",
        "IceBarLocation",
        "IceIcon",
        "ItemGroups",
        "ItemIcons",
        "ItemOrder",
        "ItemRuleShownSections",
        "ItemSections",
        "ItemSpacingOffset",
        "KeepLiveActivitiesVisible",
        "KeepsDockIconHidden",
        "KnownApplications27",
        "KnownItemTags",
        "LastRunMacOSMajor",
        "LayoutProfiles",
        "LayoutSnapshotsDisabled",
        "LayoutSnapshotsLimit",
        "LiveActivitiesCapture",
        "LiveActivitiesDownloads",
        "LockHiddenItems",
        "MacOS27ClickRestoreDelay",
        "MacOS27IceBarWaitsForRefresh",
        "MacOS27Layout",
        "MacOS27LayoutSeeded",
        "MenuBarAppearanceConfiguration",
        "MenuBarAppearanceConfigurationV2",
        "MenuBarBorderColor",
        "MenuBarBorderWidth",
        "MenuBarFullShapeInfo",
        "MenuBarHasBorder",
        "MenuBarHasShadow",
        "MenuBarShapeKind",
        "MenuBarSplitShapeInfo",
        "MenuBarTintColor",
        "MenuBarTintGradient",
        "MenuBarTintKind",
        "NewItemsPlacement",
        "NotchHubDisplays",
        "NotchHubLastTab",
        "NotchHubOpensOnHover",
        "NotificationsExcludedApps",
        "NowPlayingPlayers",
        "NowPlayingReadsAllApps",
        "OpenHiddenItemsInMenuBar",
        "RehideInterval",
        "RehideStrategy",
        "RevealAnimationStyle",
        "RevealOnChangeItems",
        "RevealRules",
        "ScreenRecordingOffered",
        "SectionDividerStyle",
        "Sections",
        "ShelfAlwaysHiddenFold",
        "ShelfAlwaysHiddenFoldOpen",
        "ShelfDragsTiles",
        "ShelfFindsByTyping",
        "ShelfLayout",
        "ShelfShowsClosedApps",
        "ShelfStyle",
        "ShowAllSectionsOnUserDrag",
        "ShowIceIcon",
        "ShowOnClick",
        "ShowOnHover",
        "ShowOnHoverDelay",
        "ShowOnScroll",
        "ShowSectionDividers",
        "ShowsHiddenItemCount",
        "ShowsNotchOverflowInIceBar",
        "SmartCategories",
        "SpacerCount",
        "SpacerWidth",
        "StandInIcons",
        "SyncsSettingsWithICloud",
        "SystemItemsMayHide",
        "TempShowInterval",
        "TimersBoard",
        "TimersFinishSound",
        "TitleChangingItemOwners",
        "UsageSuggestionsEnabled",
        "UseIceBar",
        "WhatsNewLastSeenVersion",
        "WhatsNewShowsAfterUpdate",
        "WidgetShortcutNames",
        "Widgets",
        "hasMigrated0_10_0",
        "hasMigrated0_10_1",
        "hasMigrated0_11_10",
        "hasMigrated0_11_13",
        "hasMigrated0_11_13_1",
        "hasMigrated0_8_0",
    ]

    /// Released names removed on purpose, each with the reason. A settings file that still
    /// carries one is read as any unknown key: ignored.
    private static let retiredRawValues: Set<String> = [
        // Settings sync of the 0.0.7 betas; nothing read or wrote it since 0.0.7, and
        // settings sync was dropped on 2026-11-21.
        "SyncsSettingsWithICloud",
    ]

    @Test("Every stored setting name of 1.0.5 still exists")
    func everyReleasedNameStillExists() {
        let current = Set(Defaults.Key.allCases.map(\.rawValue))
        let missing = Self.releasedRawValues.filter { !current.contains($0) && !Self.retiredRawValues.contains($0) }
        #expect(missing.isEmpty, "Missing or renamed keys: \(missing)")
    }

    @Test("A retired name is really gone and was really released")
    func retiredNamesAreGone() {
        let current = Set(Defaults.Key.allCases.map(\.rawValue))
        #expect(Self.retiredRawValues.isDisjoint(with: current))
        #expect(Self.retiredRawValues.isSubset(of: Set(Self.releasedRawValues)))
    }

    @Test("The pinned list holds each name once")
    func pinnedListHasNoDuplicates() {
        #expect(Set(Self.releasedRawValues).count == Self.releasedRawValues.count)
    }

    @Test("The raw value of the Ice import flag never changes")
    func importFlagNeverChanges() {
        #expect(Defaults.Key.hasImportedPreviousSettings.rawValue == "HasImportedIceSettings")
    }
}
