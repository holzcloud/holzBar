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

    /// The place of the setting's row in the Settings window; settings without a row sort last.
    static func sortIndex(of key: Defaults.Key) -> Int {
        entry(for: key).flatMap { order[$0.id] } ?? Int.max
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
        ]
        return values.filter { entry(for: $0.key) != nil }
    }

    /// How a value reads in the preview: the switches as "On" and "Off", a list or a structure as
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
        case .number(let number):
            number.formatted()
        case .choice(let raw):
            String(raw)
        }
    }
}
