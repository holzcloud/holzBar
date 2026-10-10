//
//  ScriptOutput.swift
//  holzBar
//

import Foundation

/// The bytes a script wrote to one stream, kept up to a limit; the rest is counted and dropped.
///
/// The runner reads each pipe to its end so a chatty script never blocks, and appends what it
/// read here. Memory never grows beyond the limit (D-07, T-11-M2).
nonisolated struct ScriptOutputBuffer: Equatable, Sendable {
    /// The most bytes kept.
    let limit: Int
    /// The bytes kept: the first ``limit`` bytes the script wrote.
    private(set) var data = Data()
    /// How many bytes were read after the limit was reached and dropped.
    private(set) var droppedByteCount = 0

    init(limit: Int) {
        self.limit = max(limit, 0)
    }

    /// Keeps as much of the chunk as fits and counts the rest.
    mutating func append(_ chunk: Data) {
        let room = limit - data.count
        guard chunk.count > room else {
            data.append(chunk)
            return
        }
        if room > 0 {
            data.append(chunk.prefix(room))
        }
        droppedByteCount += chunk.count - max(room, 0)
    }
}

/// Turns what a script printed into text holzBar may show.
///
/// A script's output is data. The line this makes is shown as plain text only and is never
/// parsed as a URL, a path, a command, markup or an attributed string, and never logged or
/// stored (D-08, T-11-M3).
nonisolated enum ScriptOutput {
    /// The most characters of the line that is kept.
    static let maximumDisplayLength = 80

    /// The first line of the output that has text, on one line, without control, format
    /// (such as a right-to-left override), separator, private-use or unassigned characters,
    /// with runs of white space as one space, and cut to ``maximumDisplayLength`` characters
    /// with an ellipsis. It is empty when the output has no text. Bytes that are not UTF-8
    /// become the replacement character.
    static func displayLine(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        var line = String.UnicodeScalarView()
        var lastWasSpace = true
        // The text is cut at "\n" and "\r" first; the first line with text wins.
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\r" {
                if let result = finish(line) {
                    return result
                }
                line = String.UnicodeScalarView()
                lastWasSpace = true
                continue
            }
            if scalar.properties.isWhitespace {
                if !lastWasSpace {
                    line.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                continue
            default:
                line.append(scalar)
                lastWasSpace = false
            }
        }
        return finish(line) ?? ""
    }

    /// The finished line, trimmed and cut, or `nil` when nothing is left of it.
    private static func finish(_ line: String.UnicodeScalarView) -> String? {
        let cleaned = String(line).trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else {
            return nil
        }
        guard cleaned.count > maximumDisplayLength else {
            return cleaned
        }
        let cut = cleaned.prefix(maximumDisplayLength - 1).trimmingCharacters(in: .whitespaces)
        return cut + "\u{2026}"
    }
}

/// What the last run of a script left behind: kept in memory only, never persisted or logged.
nonisolated struct ScriptRunRecord: Equatable, Sendable {
    /// When the run ended.
    var date: Date
    /// How it ended.
    var termination: ScriptTermination
    /// The cleaned first line of its output, at most ``ScriptOutput/maximumDisplayLength``
    /// characters; empty when it printed nothing.
    var displayLine: String
}
