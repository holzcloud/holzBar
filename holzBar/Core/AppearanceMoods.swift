//
//  AppearanceMoods.swift
//  holzBar
//

import Foundation

/// The rules for the names of moods: saved looks of the menu bar that one click, a rule or the
/// command palette switches to.
nonisolated enum MoodNaming {
    /// The most moods that can be saved.
    static let maximumCount = 12

    /// The longest name, in characters.
    static let maximumNameLength = 40

    /// The name without control, format, bidirectional and private-use characters, trimmed and
    /// cut to ``maximumNameLength``; `nil` when nothing is left.
    static func cleaned(_ name: String) -> String? {
        let scalars = name.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator:
                false
            default:
                true
            }
        }
        var text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > maximumNameLength {
            text = String(text.prefix(maximumNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.isEmpty ? nil : text
    }

    /// The name, or the name with " 2", " 3" … when another mood already has it (ignoring case).
    ///
    /// - Parameter reserved: Names no saved mood may take, such as the built-in mood's
    ///   identifier and label (``BuiltInMood/reservedNames(label:)``).
    static func unique(_ name: String, among existing: [String], reserved: [String] = []) -> String {
        let taken = Set((existing + reserved).map { $0.lowercased() })
        guard taken.contains(name.lowercased()) else {
            return name
        }
        var number = 2
        while true {
            let suffix = " \(number)"
            let candidate = String(name.prefix(maximumNameLength - suffix.count)) + suffix
            if !taken.contains(candidate.lowercased()) {
                return candidate
            }
            number += 1
        }
    }
}

/// A mood holzBar ships beside the user's moods: "Readable menu bar", for Liquid Glass.
///
/// It is stored by its identifier, never by its localized label (in automation rules, in
/// palette commands and as the current mood), and it is shown by its label. It patches only
/// the tint and the border of the current look; it is not an entry of the saved list, so it
/// has no delete button, cannot be renamed and does not count toward
/// ``MoodNaming/maximumCount``.
nonisolated enum BuiltInMood {
    /// The reserved identifier that stands for the mood wherever a mood name is stored.
    static let readableMenuBarID = "holzbar.readable-menu-bar"

    /// The label in English, which no saved mood may take in any language.
    static let englishLabel = "Readable menu bar"

    /// The tint in the light appearance: the design's elevated ground.
    static let lightTint = DesignTokens.Light.groundElevated

    /// The tint in the dark appearance: the design's elevated ground.
    static let darkTint = DesignTokens.Dark.groundElevated

    /// The border in the light appearance while Increase Contrast is on.
    static let lightBorder = DesignTokens.IncreasedContrast.Light.stroke

    /// The border in the dark appearance while Increase Contrast is on.
    static let darkBorder = DesignTokens.IncreasedContrast.Dark.stroke

    /// The width of the border, in points.
    static let borderWidth = 1.0

    /// The names a saved mood cannot take: the identifier, the label in the user's language
    /// and the label in English.
    static func reservedNames(label: String) -> [String] {
        [readableMenuBarID, label, englishLabel]
    }
}
