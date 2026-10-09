//
//  SyncRowOrdering.swift
//  holzBar
//

import Foundation

/// The part of the Settings window a setting belongs to, in the order the sheet lists rows (28-UI-SPEC "The conflict sheet"):
/// General, Advanced, Hotkeys, Appearance, Groups, Items, Menu bar arrangement, Profiles.
nonisolated enum SyncRowCategory: Int, Comparable, Sendable {
    case general
    case advanced
    case hotkeys
    case appearance
    case groups
    case items
    case arrangement
    case profiles

    static func < (lhs: SyncRowCategory, rhs: SyncRowCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: Table

    /// The category of a stored key, or `nil` when the key is not a unit of the rows (a key that stays on this Mac, and the
    /// set of known applications). The switch has no `default`, so a new `Defaults.Key` does not compile until it has one.
    static func category(ofKey key: Defaults.Key) -> SyncRowCategory? {
        switch key {
        case .showHolzBarIcon,
            .holzBarIcon,
            .customHolzBarIconIsTemplate,
            .useShelf,
            .shelfLocation,
            .shelfDisplays,
            .showsNotchOverflowInShelf,
            .showOnClick,
            .showOnHover,
            .showOnScroll,
            .showOnHoverDelay,
            .autoRehide,
            .rehideStrategy,
            .rehideInterval,
            .tempShowInterval,
            .itemSpacingOffset,
            .holzBarIconShowsCaptureDot:
            .general
        case .enableAlwaysHiddenSection,
            .showAllSectionsOnUserDrag,
            .sectionDividerStyle,
            .hideApplicationMenus,
            .keepsDockIconHidden,
            .enableSecondaryContextMenu,
            .newItemsPlacement,
            .keepLiveActivitiesVisible,
            .autoZenWhileSharingScreen,
            .openHiddenItemsInMenuBar,
            .spacerCount,
            .spacerWidth:
            .advanced
        case .hotkeys:
            .hotkeys
        case .menuBarAppearanceConfigurationV2:
            .appearance
        case .itemGroups:
            .groups
        case .itemIcons, .revealRules, .revealOnChangeItems:
            .items
        case .macOS27Layout:
            .arrangement
        case .layoutProfiles:
            .profiles
        case .knownApplications27,
            .itemSections,
            .knownItemTags,
            .titleChangingItemOwners,
            .macOS27LayoutSeeded,
            .hasMigrated0_8_0,
            .hasMigrated0_10_0,
            .hasMigrated0_10_1,
            .hasMigrated0_11_10,
            .hasMigrated0_11_13,
            .hasMigrated0_11_13_1,
            .hasImportedPreviousSettings,
            .currentLayoutProfile,
            .macOS27ClickRestoreDelay,
            .macOS27ShelfWaitsForRefresh,
            .syncsSettingsWithICloud,
            .debugDropsBarrierExitEvent,
            .debugHangsItemImageCapture,
            .menuBarHasBorder,
            .menuBarBorderColor,
            .menuBarBorderWidth,
            .menuBarHasShadow,
            .menuBarTintKind,
            .menuBarTintColor,
            .menuBarTintGradient,
            .menuBarShapeKind,
            .menuBarFullShapeInfo,
            .menuBarSplitShapeInfo,
            .menuBarAppearanceConfiguration,
            .showSectionDividers,
            .canToggleAlwaysHiddenSection,
            .sections:
            nil
        }
    }

    /// The category of each whole unit, by name, and of each family, by name.
    private static let table: (wholes: [String: SyncRowCategory], families: [String: SyncRowCategory]) = {
        var wholes: [String: SyncRowCategory] = [:]
        var families: [String: SyncRowCategory] = [:]
        for key in Defaults.Key.allCases {
            guard let category = category(ofKey: key) else {
                continue
            }
            switch SyncUnitTable.keyClass(key) {
            case .whole(let unit):
                wholes[unit] = category
            case .holzBarIconPart:
                wholes[SyncUnitTable.holzBarIconUnit] = category
            case .split(let family):
                families[family] = category
            case .layout27:
                families[SyncUnitTable.layout27Family] = category
            case .profiles:
                families[SyncUnitTable.profilesFamily] = category
            case .knownApplications27, .local:
                continue
            }
        }
        return (wholes, families)
    }()

    /// The category of a unit, or `nil` for a unit this build does not know.
    static func known(_ unit: SyncUnitKey) -> SyncRowCategory? {
        switch unit {
        case .whole(let name):
            table.wholes[name]
        case .split(let family, _):
            table.families[family]
        }
    }

    /// The category of a unit. A unit this build does not know sorts with Advanced; the sheet never asks about one, because
    /// an answer cannot write it.
    static func category(of unit: SyncUnitKey) -> SyncRowCategory {
        known(unit) ?? .advanced
    }
}

/// The order of the rows in the sheet: deterministic, never by date.
nonisolated enum SyncRowOrdering {
    /// `rows` by the category of their unit, then by `label` compared the way the Finder compares names, then by unit key, so
    /// the same rows give the same order whatever order they come in.
    static func sorted(_ rows: [SyncRow], label: (SyncRow) -> String) -> [SyncRow] {
        let labelled = rows.map { (row: $0, category: SyncRowCategory.category(of: $0.unit), label: label($0)) }
        return labelled.sorted { lhs, rhs in
            if lhs.category != rhs.category {
                return lhs.category < rhs.category
            }
            switch lhs.label.localizedStandardCompare(rhs.label) {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                return lhs.row.unit < rhs.row.unit
            }
        }
        .map(\.row)
    }
}
