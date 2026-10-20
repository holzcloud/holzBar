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
    static func unique(_ name: String, among existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
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
