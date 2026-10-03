//
//  URLPrompt.swift
//  holzBar
//

import Foundation

/// The question holzBar asks before it performs a `holzbar://` command that changes
/// something lasting (`URLCommand.Decision.ask`).
///
/// Any app can open these URLs, as often as it likes, and with any text in them. So the
/// question never shows text from the URL itself, only names holzBar has stored, cleaned
/// up (``displayName(_:)``); at most one question is open at a time; and after the user
/// declines one, further questions are not asked for a while (``Gate``).
nonisolated enum URLPrompt {
    /// The most characters of a name a question shows.
    static let maximumNameLength = 40

    /// `name` as a question shows it: on one line, without control or formatting
    /// characters (such as a right-to-left override), runs of white space as one space,
    /// and cut to ``maximumNameLength`` characters with an ellipsis.
    static func displayName(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in name.unicodeScalars {
            if scalar.properties.isWhitespace {
                // Line breaks, tabs and runs of spaces become one space.
                if !lastWasSpace {
                    scalars.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                continue
            default:
                scalars.append(scalar)
                lastWasSpace = false
            }
        }
        let cleaned = String(scalars).trimmingCharacters(in: .whitespaces)
        guard cleaned.count > maximumNameLength else {
            return cleaned
        }
        let cut = cleaned.prefix(maximumNameLength - 1).trimmingCharacters(in: .whitespaces)
        return cut + "\u{2026}"
    }

    /// Decides whether holzBar may ask now.
    nonisolated struct Gate: Sendable {
        /// How long holzBar asks nothing after the user declined a question.
        static let quietPeriod: Duration = .seconds(30)

        /// Whether a question is open.
        private(set) var isAsking = false

        /// When the user last declined a question.
        private var lastDeclined: ContinuousClock.Instant?

        /// Starts a question, if one may be asked now.
        ///
        /// - Returns: `false` while another question is open, or within ``quietPeriod`` of
        ///   a declined one; the command is then ignored.
        mutating func begin(at now: ContinuousClock.Instant) -> Bool {
            guard !isAsking else {
                return false
            }
            if let lastDeclined, now < lastDeclined.advanced(by: Self.quietPeriod) {
                return false
            }
            isAsking = true
            return true
        }

        /// Ends the open question with the user's answer.
        mutating func end(approved: Bool, at now: ContinuousClock.Instant) {
            isAsking = false
            lastDeclined = approved ? nil : now
        }
    }
}
