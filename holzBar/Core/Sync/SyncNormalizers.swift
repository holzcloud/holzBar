//
//  SyncNormalizers.swift
//  holzBar
//

import Foundation

/// Turns the stored value of a JSON unit into one canonical value, so that two builds that
/// store the same setting differently still compare equal (analysis section 4.6.2).
///
/// Each closure returns the canonical value, or `nil` when the value is not valid for the
/// unit. The app replaces ``appearance`` and ``itemGroups`` with normalizers that decode and
/// re-encode through the models, so a load-time re-encode by another build compares equal;
/// ``canonical`` is the Core default, which only sorts the keys of the JSON.
nonisolated struct SyncNormalizers: Sendable {
    /// The menu bar appearance (`MenuBarAppearanceConfigurationV2`), stored as JSON data.
    let appearance: @Sendable (SyncValue) -> SyncValue?
    /// The item groups (`ItemGroups`), stored as JSON data.
    let itemGroups: @Sendable (SyncValue) -> SyncValue?
    /// The holzBar icon unit: a dictionary with the image data (`icon`) and the template
    /// flag (`template`).
    let holzBarIcon: @Sendable (SyncValue) -> SyncValue?

    init(
        appearance: @escaping @Sendable (SyncValue) -> SyncValue?,
        itemGroups: @escaping @Sendable (SyncValue) -> SyncValue?,
        holzBarIcon: @escaping @Sendable (SyncValue) -> SyncValue?
    ) {
        self.appearance = appearance
        self.itemGroups = itemGroups
        self.holzBarIcon = holzBarIcon
    }

    /// The names of the fields of the icon unit.
    static let iconField = "icon"
    static let templateField = "template"

    /// The Core defaults: JSON units are re-encoded with sorted keys, the icon is checked
    /// for its shape only.
    static let canonical = SyncNormalizers(
        appearance: canonicalJSON,
        itemGroups: canonicalJSON,
        holzBarIcon: structuralIcon
    )

    /// `value` as JSON data with sorted keys; `nil` unless it is data that holds a JSON
    /// object or array.
    @Sendable
    static func canonicalJSON(_ value: SyncValue) -> SyncValue? {
        guard
            case .data(let data) = value,
            let object = try? JSONSerialization.jsonObject(with: data, options: []),
            object is [String: Any] || object is [Any],
            let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        else {
            return nil
        }
        return .data(encoded)
    }

    /// `value` when it is a dictionary of image data and a template flag, with at least one
    /// of them.
    @Sendable
    static func structuralIcon(_ value: SyncValue) -> SyncValue? {
        guard let fields = value.dictionaryValue, !fields.isEmpty else {
            return nil
        }
        for (name, field) in fields {
            switch (name, field) {
            case (iconField, .data(let data)) where !data.isEmpty:
                continue
            case (templateField, .bool):
                continue
            default:
                return nil
            }
        }
        return value
    }
}
