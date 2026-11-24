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
nonisolated enum PreviousAppImport {
    /// The kind of value a rule takes and how it checks it.
    private enum Translation {
        /// A Boolean, stored as a Boolean.
        case bool

        /// The value as it may be validated and written, or `nil` when it has the wrong kind.
        func accept(_ value: Any) -> Any? {
            switch self {
            case .bool:
                SettingsSchema.matches(value, .bool) ? value : nil
            }
        }

        /// The validated value as the preview shows it, or `nil` when it is not of this kind.
        func shown(_ value: Any) -> ImportValue? {
            switch self {
            case .bool:
                (value as? Bool).map(ImportValue.bool)
            }
        }
    }

    /// The holzBar setting a key of the source belongs to, and how its value is read.
    private struct Rule {
        let target: Defaults.Key
        let translation: Translation
    }

    /// Thaw's rules by the stored name in Thaw's defaults: the twelve Booleans whose meaning is
    /// the same in both apps.
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
    ]

    private static func rules(for source: ImportSource) -> [String: Rule] {
        switch source {
        case .thaw: thaw
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
    ///   - excludedPrefixes: Keys that start with one of these are never taken
    ///     (`SettingsBackup.excludedKeyPrefixes`).
    ///   - ownBundleIdentifier: holzBar's own bundle identifier.
    static func plan(
        source: ImportSource,
        settings: [String: Any],
        current: [Defaults.Key: ImportValue],
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
        changes.sort { $0.key.rawValue < $1.key.rawValue }
        let omissions: [ImportOmission] = []
        let ignored = max(0, settings.count - changes.count - unchanged - omissions.count)
        return ImportPlan(source: source, changes: changes, omissions: omissions, ignoredCount: ignored, writes: writes)
    }
}
