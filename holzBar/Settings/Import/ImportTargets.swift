//
//  ImportTargets.swift
//  holzBar
//

import Foundation

/// What the import preview needs to know about each holzBar setting an import may change: the
/// row of the Settings window that holds it (so the preview names it as Settings does), where that
/// row sits (so the list reads in the order of the panes), what the setting holds now, and how
/// a value reads.
///
/// A setting whose row does not exist on this macOS has no label, so it is not a target here:
/// the plan counts it as ignored and never names it.
enum ImportTargets {
    /// The catalogue entry whose row binds each setting an import may change.
    private static let entries: [Defaults.Key: SettingsEntry] = [
        .autoRehide: .hidingAutoRehide,
        .autoZenWhileSharingScreen: .hidingAutoZen,
        .enableAlwaysHiddenSection: .layoutAlwaysHidden,
        .enableSecondaryContextMenu: .advancedSecondaryContextMenu,
        .hideApplicationMenus: .advancedHideAppMenus,
        .openHiddenItemsInMenuBar: .hidingOpenInMenuBar,
        .showAllSectionsOnUserDrag: .advancedShowAllSectionsOnDrag,
        .showOnClick: .hidingShowOnClick,
        .showOnHover: .hidingShowOnHover,
        .showOnScroll: .hidingShowOnScroll,
        .showHolzBarIcon: .generalIcon,
        .useShelf: .shelfUse,
        .rehideStrategy: .hidingRehideStrategy,
        .rehideInterval: .hidingRehideInterval,
        .showOnHoverDelay: .hidingHoverDelay,
        .tempShowInterval: .hidingTempShowInterval,
    ]

    /// The Hotkeys-pane entry of each hotkey action, by the action's stored name. Its label is the
    /// name the action has in Settings.
    private static let hotkeyEntries: [String: SettingsEntry] = [
        HotkeyAction.toggleHiddenSection.rawValue: .hotkeysToggleHidden,
        HotkeyAction.toggleAlwaysHiddenSection.rawValue: .hotkeysToggleAlwaysHidden,
        HotkeyAction.showHiddenSectionTemporarily.rawValue: .hotkeysShowForAMoment,
        HotkeyAction.searchMenuBarItems.rawValue: .hotkeysSearch,
        HotkeyAction.showItemHints.rawValue: .hotkeysItemHints,
        HotkeyAction.openCommandPalette.rawValue: .hotkeysCommandPalette,
        HotkeyAction.enableShelf.rawValue: .hotkeysShelf,
        HotkeyAction.toggleAutoRehide.rawValue: .hotkeysAutoRehide,
        HotkeyAction.toggleZenMode.rawValue: .hotkeysZenMode,
        HotkeyAction.toggleKeepAwake.rawValue: .hotkeysKeepAwake,
        HotkeyAction.toggleApplicationMenus.rawValue: .hotkeysAppMenus,
        HotkeyAction.toggleNotchHub.rawValue: .hotkeysNotchHub,
    ]

    /// The position of every entry of this macOS in the Settings window, in sidebar order.
    private static let order: [String: Int] = Dictionary(
        uniqueKeysWithValues: SettingsCatalog.all.enumerated().map { ($1.id, $0) }
    )

    /// The entry whose row binds the setting, or `nil` when the row does not exist on this macOS.
    static func entry(for key: Defaults.Key) -> SettingsEntry? {
        guard let entry = entries[key], order[entry.id] != nil else {
            return nil
        }
        return entry
    }

    /// The entry of a hotkey action, by its stored name, or `nil` when the action has no row on
    /// this macOS: such an action is not offered to the plan, so it is ignored and never named.
    static func hotkeyEntry(for action: String) -> SettingsEntry? {
        guard let entry = hotkeyEntries[action], order[entry.id] != nil else {
            return nil
        }
        return entry
    }

    /// The entry whose row names a change: the hotkey's row for a hotkey change, the setting's
    /// row for any other.
    static func entry(for change: ImportChange) -> SettingsEntry? {
        if let action = change.hotkeyAction {
            return hotkeyEntry(for: action)
        }
        return entry(for: change.key)
    }

    /// The place of the setting's row in the Settings window; settings without a row sort last.
    static func sortIndex(of key: Defaults.Key) -> Int {
        entry(for: key).flatMap { order[$0.id] } ?? Int.max
    }

    /// The place of a change's row in the Settings window; a change without a row sorts last.
    static func sortIndex(of change: ImportChange) -> Int {
        entry(for: change).flatMap { order[$0.id] } ?? Int.max
    }

    /// What each target holds now: the effective value of the models the rows bind, for every
    /// target that has a label on this macOS.
    static func currentValues(in settings: AppSettings) -> [Defaults.Key: ImportValue] {
        let general = settings.general
        let advanced = settings.advanced
        let values: [Defaults.Key: ImportValue] = [
            .autoRehide: .bool(general.autoRehide),
            .autoZenWhileSharingScreen: .bool(advanced.autoZenWhileSharingScreen),
            .enableAlwaysHiddenSection: .bool(advanced.enableAlwaysHiddenSection),
            .enableSecondaryContextMenu: .bool(advanced.enableSecondaryContextMenu),
            .hideApplicationMenus: .bool(advanced.hideApplicationMenus),
            .openHiddenItemsInMenuBar: .bool(advanced.openHiddenItemsInMenuBar),
            .showAllSectionsOnUserDrag: .bool(advanced.showAllSectionsOnUserDrag),
            .showOnClick: .bool(general.showOnClick),
            .showOnHover: .bool(general.showOnHover),
            .showOnScroll: .bool(general.showOnScroll),
            .showHolzBarIcon: .bool(general.showHolzBarIcon),
            .useShelf: .bool(general.useShelf),
            .rehideStrategy: .choice(general.rehideStrategy.rawValue),
            .rehideInterval: .number(general.rehideInterval),
            .showOnHoverDelay: .number(advanced.showOnHoverDelay),
            .tempShowInterval: .number(advanced.tempShowInterval),
        ]
        return values.filter { entry(for: $0.key) != nil }
    }

    /// How a value reads in the preview: the switches as "On" and "Off", intervals in seconds as
    /// the system writes them, a choice by the name its pop-up shows, a list or a structure as
    /// "Changed".
    static func text(for value: ImportValue, of key: Defaults.Key) -> String {
        switch value {
        case .bool(let isOn):
            if isOn {
                String(localized: "On")
            } else {
                String(localized: "Off")
            }
        case .composite:
            String(localized: "Changed")
        case .number(let seconds):
            Measurement(value: seconds, unit: UnitDuration.seconds).formatted(
                .measurement(
                    width: .narrow,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(0...1))
                )
            )
        case .choice(let raw):
            choiceName(raw, of: key)
        }
    }

    /// The name of a choice as the pop-up of its setting shows it. `RehideStrategy.localized` is a
    /// `LocalizedStringKey`, which cannot be turned into the text a VoiceOver label needs, so the
    /// names are written out here from the same catalogue keys.
    private static func choiceName(_ raw: Int, of key: Defaults.Key) -> String {
        switch (key, RehideStrategy(rawValue: raw)) {
        case (.rehideStrategy, .smart):
            String(localized: "Smart")
        case (.rehideStrategy, .timed):
            String(localized: "After a fixed time")
        case (.rehideStrategy, .focusedApp):
            String(localized: "When the app changes")
        default:
            raw.formatted()
        }
    }
}
