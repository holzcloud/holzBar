//
//  LegacySettingsMigration.swift
//  holzBar
//

import Foundation

/// Brings the settings of an old Ice version into the current schema, in one step.
///
/// Ice migrated its settings at every launch, one step per version that changed them, and
/// marked each step done with a `hasMigrated…` flag. holzBar runs the same steps once, on
/// the settings it imports from Ice, so nothing migrates at launch. A step runs only when
/// its flag is not set in the imported settings; afterwards every flag is set.
///
/// The steps work on the stored key names (the raw values of `Defaults.Key`). The
/// appearance of Ice before 0.11.10 needs the app's appearance types, so the app converts
/// it (see ``needsAppearanceConversion(_:)``).
nonisolated enum LegacySettingsMigration {
    /// The flags of the old migration steps, one per Ice version, in order.
    static let migrationFlags = [
        "hasMigrated0_8_0",
        "hasMigrated0_10_0",
        "hasMigrated0_10_1",
        "hasMigrated0_11_10",
        "hasMigrated0_11_13",
        "hasMigrated0_11_13_1",
    ]

    /// The menu bar sections as Ice stored them before 0.8.0, as JSON data.
    static let sectionsKey = "Sections"

    /// The hotkeys: action raw value to stored key combination (see ``HotkeyStorage``).
    static let hotkeysKey = "Hotkeys"

    /// Whether Ice before 0.11.13 drew section dividers.
    static let showSectionDividersKey = "ShowSectionDividers"

    /// The section divider style: 0 no divider, 1 chevron.
    static let sectionDividerStyleKey = "SectionDividerStyle"

    /// The menu bar appearance as Ice stored it before 0.11.10.
    static let appearanceV1Key = "MenuBarAppearanceConfiguration"

    /// The prefix of the positions and visibility macOS stores for status items.
    static let statusItemKeyPrefix = "NSStatusItem"

    /// The hotkey actions of the hidden and always-hidden sections, by the section names
    /// Ice used before 0.8.0.
    private static let sectionHotkeyActions = [
        "Hidden": HotkeyAction.toggleHiddenSection.rawValue,
        "Always Hidden": HotkeyAction.toggleAlwaysHiddenSection.rawValue,
    ]

    /// Returns the settings migrated to the current schema.
    static func migrate(_ settings: [String: Any]) -> [String: Any] {
        var migrated = settings

        // Ice 0.8.0: the hotkeys of the hidden and always-hidden sections moved out of the
        // stored sections into the hotkeys, and the sections were no longer stored.
        if !hasRun("hasMigrated0_8_0", in: settings) {
            moveSectionHotkeys(in: &migrated)
        }

        // Ice 0.8.0, 0.10.0, 0.10.1 and 0.11.13.1 renamed and reset the status item
        // positions. They belong to Ice's own items, so none are carried over.
        let statusItemSteps = ["hasMigrated0_8_0", "hasMigrated0_10_0", "hasMigrated0_10_1", "hasMigrated0_11_13_1"]
        if !statusItemSteps.allSatisfy({ hasRun($0, in: settings) }) {
            for key in migrated.keys where key.hasPrefix(statusItemKeyPrefix) {
                migrated.removeValue(forKey: key)
            }
        }

        // Ice 0.11.10: the appearance moved to a new configuration. The app converts it,
        // as it needs the app's appearance types (see `needsAppearanceConversion`).

        // Ice 0.11.13: section dividers became a divider style.
        if !hasRun("hasMigrated0_11_13", in: settings) {
            let showsDividers = settings[showSectionDividersKey] as? Bool ?? false
            migrated[sectionDividerStyleKey] = showsDividers ? 1 : 0
            migrated.removeValue(forKey: showSectionDividersKey)
        }

        for flag in migrationFlags {
            migrated[flag] = true
        }
        return migrated
    }

    /// Returns a Boolean value that indicates whether the settings hold an appearance of
    /// Ice before 0.11.10 that still needs converting.
    static func needsAppearanceConversion(_ settings: [String: Any]) -> Bool {
        !hasRun("hasMigrated0_11_10", in: settings) && settings[appearanceV1Key] is Data
    }

    /// Returns a Boolean value that indicates whether the step with the given flag has run.
    private static func hasRun(_ flag: String, in settings: [String: Any]) -> Bool {
        settings[flag] as? Bool == true
    }

    /// Moves the hotkeys stored with the sections (Ice before 0.8.0) into the hotkeys and
    /// removes the sections. Sections that cannot be read are removed without a hotkey.
    private static func moveSectionHotkeys(in settings: inout [String: Any]) {
        guard let data = settings.removeValue(forKey: sectionsKey) as? Data else {
            return
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let sections = object as? [[String: Any]]
        else {
            return
        }
        var hotkeys = settings[hotkeysKey] as? [String: Any] ?? [:]
        var changed = false
        for section in sections {
            guard
                let name = section["name"] as? String,
                let action = sectionHotkeyActions[name],
                let hotkey = section["hotkey"] as? [String: Any],
                let key = hotkey["key"] as? Int,
                let modifiers = hotkey["modifiers"] as? Int
            else {
                continue
            }
            hotkeys[action] = HotkeyStorage.encode(key: key, modifiers: modifiers)
            changed = true
        }
        if changed {
            settings[hotkeysKey] = hotkeys
        }
    }
}
