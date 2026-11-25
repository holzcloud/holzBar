//
//  InputSourceLabel.swift
//  holzBar
//

import Foundation

/// How an input source is named in the closed notch's flash, as pure rules (D-09).
///
/// The flash holds a short code beside the keyboard symbol, such as "DE" or "EN", and the full
/// localized name as its second text. The system reports the source's languages and its localized
/// name; this decides what shows and when the flash is worth showing at all.
nonisolated enum InputSourceLabel {
    /// The most characters of a code.
    static let maximumCodeLength = 16
    /// The fewest enabled input sources for which a change is shown: with one there is nothing to
    /// switch between.
    static let minimumSources = 2

    /// The short code of an input source: the first language, up to a "-" or "_", upper case, two
    /// letters (`["en-US"]` gives "EN"); without a language the first two characters of the
    /// localized name; at most ``maximumCodeLength`` characters.
    static func shortCode(languages: [String], localizedName: String) -> String {
        if let first = languages.first {
            let language = first.prefix { $0 != "-" && $0 != "_" }
            if !language.isEmpty {
                return String(language.uppercased().prefix(2))
            }
        }
        return String(localizedName.prefix(min(2, maximumCodeLength)))
    }

    /// Whether a change of the source is shown, given how many input sources are enabled.
    static func shows(enabledCount: Int) -> Bool {
        enabledCount >= minimumSources
    }
}
