//
//  PreviousAppImport.swift
//  holzBar
//

import Foundation

/// An app whose settings holzBar can take over, with the name it stores them under.
nonisolated enum ImportSource: String, CaseIterable, Sendable {
    case thaw

    /// The bundle identifier of the app, which names its defaults domain. It comes from the
    /// app's source, not from a probe: a build with another identifier shows as not found, and
    /// holzBar never guesses another domain.
    var bundleIdentifier: String {
        switch self {
        case .thaw: "com.stonerl.Thaw"
        }
    }

    /// The product's name, shown as it is and never translated.
    var productName: String {
        switch self {
        case .thaw: "Thaw"
        }
    }
}

/// A setting's value as the import preview shows and compares it.
nonisolated enum ImportValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    /// The raw value of a choice, such as `RehideStrategy`.
    case choice(Int)
    /// A value that is a list or a structure; the preview says only that it changes.
    case composite
}

/// One setting the import would change.
nonisolated struct ImportChange: Equatable, Sendable {
    let key: Defaults.Key
    /// The action of a hotkey change, `nil` for every other setting.
    let hotkeyAction: String?
    let before: ImportValue
    let after: ImportValue
}

/// A setting of the source that the import leaves out on purpose and names in the preview.
nonisolated struct ImportOmission: Equatable, Sendable {
    let key: Defaults.Key
    let hotkeyAction: String?
}

/// What the import needs to know about holzBar's hotkeys to take another app's over safely.
///
/// The hotkey types live in the app (``HotkeyAction`` and ``HotkeyStorage`` are not part of this
/// file's Foundation-only core), so the importer hands the two rules in: which actions holzBar
/// has, and whether a stored combination is one holzBar would load.
nonisolated struct ImportHotkeyRules: Sendable {
    /// The stored names of the hotkey actions holzBar knows and shows in Settings. A hotkey of
    /// the source for any other action is ignored.
    let knownActions: Set<String>
    /// Whether the stored combination decodes and holzBar would load it: a key code in range, no
    /// unknown modifier bit and the same modifier rule the hotkey recorder applies. A combination
    /// that fails is never imported, because holzBar would refuse it at launch or, worse, take a
    /// bare key from every app.
    let isValid: @Sendable (Data) -> Bool
}

/// What an import would do: the settings it changes, the ones it names as not imported, how
/// many other keys it ignores, and the validated values it would write.
nonisolated struct ImportPlan {
    let source: ImportSource
    let changes: [ImportChange]
    let omissions: [ImportOmission]
    /// The keys of the source that give neither a change, an equal value nor an omission: keys
    /// holzBar has no setting for, keys of the never-import list, values of the wrong kind, and
    /// settings without a label on this macOS. None is named.
    let ignoredCount: Int
    /// The raw values to write, by holzBar's stored name. Only keys of `changes`.
    let writes: [String: Any]
}

/// Maps another app's settings onto holzBar's and lists what would change.
///
/// There is no verbatim copy of a settings domain. Thaw keeps the stored names Ice used, but
/// several of them carry values whose meaning differs between the apps, so every key goes
/// through a typed rule: it names the holzBar setting it belongs to, the kind of value it
/// takes, and nothing without a rule is ever written. The values then go through holzBar's own
/// validation (`Defaults.Key.validatedSettings`) again, so a wrong kind or an out-of-range
/// number never reaches the defaults.
///
/// The merge replaces only the keys it carries. A setting the source does not have stays as it
/// is: a plan never removes a key, unlike the replacing import of holzBar's own settings file.
/// The hotkeys merge per action: an action of the source that holzBar knows and whose
/// combination holzBar would load replaces that action's combination, and every other holzBar
/// hotkey, shortcuts of items and profiles included, stays exactly as it is.
nonisolated enum PreviousAppImport {
    /// The kind of value a rule takes and how it checks it.
    private enum Translation {
        /// A Boolean, stored as a Boolean.
        case bool
        /// A finite number; the target's number rule clamps it to its range.
        case number
        /// The raw value of a choice: a whole number inside the range, nothing else.
        case choice(ClosedRange<Int>)

        /// The value as it may be validated and written, or `nil` when it has the wrong kind.
        func accept(_ value: Any) -> Any? {
            switch self {
            case .bool:
                return SettingsSchema.matches(value, .bool) ? value : nil
            case .number:
                guard SettingsSchema.matches(value, .number), let number = value as? NSNumber, number.doubleValue.isFinite else {
                    return nil
                }
                return number
            case .choice(let range):
                guard SettingsSchema.matches(value, .number), let number = value as? NSNumber else {
                    return nil
                }
                let double = number.doubleValue
                // Compared as numbers before the conversion: a huge value must not trap `Int(_:)`.
                guard
                    double.isFinite,
                    double.rounded(.towardZero) == double,
                    double >= Double(range.lowerBound),
                    double <= Double(range.upperBound)
                else {
                    return nil
                }
                return NSNumber(value: Int(double))
            }
        }

        /// The validated value as the preview shows it, or `nil` when it is not of this kind.
        func shown(_ value: Any) -> ImportValue? {
            switch self {
            case .bool:
                return (value as? Bool).map(ImportValue.bool)
            case .number:
                return (value as? NSNumber).map { ImportValue.number($0.doubleValue) }
            case .choice:
                return (value as? NSNumber).map { ImportValue.choice($0.intValue) }
            }
        }
    }

    /// The holzBar setting a key of the source belongs to, and how its value is read.
    private struct Rule {
        let target: Defaults.Key
        let translation: Translation
    }

    /// Thaw's rules by the stored name in Thaw's defaults: the twelve Booleans and the three
    /// intervals whose meaning is the same in both apps, and the rehide strategy, whose raw values
    /// 0 to 2 are the same too (checked against a real file at the beta). Everything else of
    /// Thaw has no rule here, among them the enums whose raw values differ in meaning between the
    /// apps.
    private static let thaw: [String: Rule] = [
        "AutoRehide": Rule(target: .autoRehide, translation: .bool),
        "AutoZenWhileSharingScreen": Rule(target: .autoZenWhileSharingScreen, translation: .bool),
        "EnableAlwaysHiddenSection": Rule(target: .enableAlwaysHiddenSection, translation: .bool),
        "EnableSecondaryContextMenu": Rule(target: .enableSecondaryContextMenu, translation: .bool),
        "HideApplicationMenus": Rule(target: .hideApplicationMenus, translation: .bool),
        "OpenHiddenItemsInMenuBar": Rule(target: .openHiddenItemsInMenuBar, translation: .bool),
        "ShowAllSectionsOnUserDrag": Rule(target: .showAllSectionsOnUserDrag, translation: .bool),
        "ShowOnClick": Rule(target: .showOnClick, translation: .bool),
        "ShowOnHover": Rule(target: .showOnHover, translation: .bool),
        "ShowOnScroll": Rule(target: .showOnScroll, translation: .bool),
        "ShowIceIcon": Rule(target: .showHolzBarIcon, translation: .bool),
        "UseIceBar": Rule(target: .useShelf, translation: .bool),
        "RehideInterval": Rule(target: .rehideInterval, translation: .number),
        "ShowOnHoverDelay": Rule(target: .showOnHoverDelay, translation: .number),
        "TempShowInterval": Rule(target: .tempShowInterval, translation: .number),
        "RehideStrategy": Rule(target: .rehideStrategy, translation: .choice(0...2)),
    ]

    private static func rules(for source: ImportSource) -> [String: Rule] {
        switch source {
        case .thaw: thaw
        }
    }

    /// Whether the source stores hotkeys the way holzBar does: the `Hotkeys` dictionary of the
    /// action's raw value to the JSON `[key, modifiers]`. Thaw keeps Ice's form; the wrong form is
    /// ignored, never written, because every combination must pass the rules of the importer.
    private static func readsHotkeys(of source: ImportSource) -> Bool {
        switch source {
        case .thaw: true
        }
    }

    /// The stored names of a source's settings that have a rule, with the holzBar setting each
    /// belongs to.
    static func sourceNames(of source: ImportSource) -> [String: Defaults.Key] {
        rules(for: source).mapValues(\.target)
    }

    /// Plans an import.
    ///
    /// - Parameters:
    ///   - source: The app the settings come from.
    ///   - settings: The source's defaults domain, as read after the user's click.
    ///   - current: The effective value of every holzBar setting the import may change and
    ///     that has a label on this macOS. A setting that is not in it is ignored.
    ///   - currentHotkeys: holzBar's stored hotkeys now, by action. The merged `Hotkeys` write
    ///     starts from it.
    ///   - hotkeyRules: Which hotkey actions holzBar has and which combinations it would load.
    ///   - excludedPrefixes: Keys that start with one of these are never taken
    ///     (`SettingsBackup.excludedKeyPrefixes`).
    ///   - ownBundleIdentifier: holzBar's own bundle identifier.
    static func plan(
        source: ImportSource,
        settings: [String: Any],
        current: [Defaults.Key: ImportValue],
        currentHotkeys: [String: Data],
        hotkeyRules: ImportHotkeyRules,
        excludedPrefixes: [String],
        ownBundleIdentifier: String
    ) -> ImportPlan {
        let rules = rules(for: source)
        // Typed rule first: only a key with a rule, a target that has a label here and a value
        // of the right kind becomes a candidate.
        var staged: [Defaults.Key: (rule: Rule, raw: Any)] = [:]
        for (name, value) in settings {
            let isExcluded = excludedPrefixes.contains { name.hasPrefix($0) }
            guard
                !isExcluded,
                let rule = rules[name],
                current[rule.target] != nil,
                let raw = rule.translation.accept(value)
            else {
                continue
            }
            staged[rule.target] = (rule, raw)
        }
        // Then holzBar's own validation, which also clamps numbers to their range.
        let candidates = Dictionary(uniqueKeysWithValues: staged.map { ($0.key.rawValue, $0.value.raw) })
        let accepted = Defaults.Key.validatedSettings(candidates, ownBundleIdentifier: ownBundleIdentifier).accepted

        var changes: [ImportChange] = []
        var writes: [String: Any] = [:]
        var unchanged = 0
        for (target, entry) in staged {
            guard
                let value = accepted[target.rawValue],
                let after = entry.rule.translation.shown(value),
                let before = current[target]
            else {
                continue
            }
            if after == before {
                unchanged += 1
            } else {
                changes.append(ImportChange(key: target, hotkeyAction: nil, before: before, after: after))
                writes[target.rawValue] = value
            }
        }
        // Hotkeys merge per action: the write is holzBar's dictionary with the imported actions
        // replaced, never the source's dictionary as a whole.
        let hotkeys = hotkeyPlan(of: source, settings: settings, currentHotkeys: currentHotkeys, rules: hotkeyRules, excludedPrefixes: excludedPrefixes)
        var sourceKeys = settings.count
        if hotkeys.isRead {
            // The dictionary counts as the actions it holds, not as one key.
            sourceKeys += hotkeys.entryCount - 1
        }
        unchanged += hotkeys.unchanged
        if !hotkeys.changes.isEmpty {
            let merged: [String: Any] = hotkeys.merged
            let accepted = Defaults.Key.validatedSettings([Defaults.Key.hotkeys.rawValue: merged], ownBundleIdentifier: ownBundleIdentifier).accepted
            if let value = accepted[Defaults.Key.hotkeys.rawValue] {
                changes += hotkeys.changes
                writes[Defaults.Key.hotkeys.rawValue] = value
            }
        }
        changes.sort {
            ($0.key.rawValue, $0.hotkeyAction ?? "") < ($1.key.rawValue, $1.hotkeyAction ?? "")
        }
        let omissions: [ImportOmission] = []
        let ignored = max(0, sourceKeys - changes.count - unchanged - omissions.count)
        return ImportPlan(source: source, changes: changes, omissions: omissions, ignoredCount: ignored, writes: writes)
    }

    /// What the source's `Hotkeys` dictionary gives: the changed actions (each one change of a
    /// composite), how many entries it holds, how many equal holzBar's, and holzBar's dictionary
    /// with the changed actions replaced.
    private struct HotkeyPlan {
        var isRead = false
        var entryCount = 0
        var unchanged = 0
        var changes: [ImportChange] = []
        var merged: [String: Data] = [:]
    }

    private static func hotkeyPlan(
        of source: ImportSource,
        settings: [String: Any],
        currentHotkeys: [String: Data],
        rules: ImportHotkeyRules,
        excludedPrefixes: [String]
    ) -> HotkeyPlan {
        var result = HotkeyPlan(merged: currentHotkeys)
        let name = Defaults.Key.hotkeys.rawValue
        guard
            readsHotkeys(of: source),
            !excludedPrefixes.contains(where: { name.hasPrefix($0) }),
            let stored = settings[name] as? [String: Any]
        else {
            return result
        }
        result.isRead = true
        result.entryCount = stored.count
        for (action, raw) in stored {
            // Only an action holzBar has, with data that is a combination holzBar would load.
            guard rules.knownActions.contains(action), let data = raw as? Data, rules.isValid(data) else {
                continue
            }
            if currentHotkeys[action] == data {
                result.unchanged += 1
            } else {
                result.merged[action] = data
                result.changes.append(ImportChange(key: .hotkeys, hotkeyAction: action, before: .composite, after: .composite))
            }
        }
        return result
    }
}
