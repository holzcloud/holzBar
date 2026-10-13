//
//  CodeCount.swift
//  holzBar
//

import Foundation

/// The C1 line count: how much of the AppKit Layout bar a macOS 27 SwiftUI path could delete at
/// most, against how much code that path adds at least.
public enum CodeCount {
    /// The lines that open a macOS 27 scope.
    public static let markers = ["#available(macOS 27", "@available(macOS 27"]

    /// The ratio of deletable to new code a replacement must reach.
    public static let threshold = 1.3

    /// The lines that hold code: not blank, not only a comment (`//`, `///`, `/* … */`). A line
    /// with code before a comment counts.
    public static func codeLines(_ text: String) -> Int {
        var masker = Masker(text: text, maskStrings: false)
        return lines(of: masker.run()).count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The code lines inside every macOS 27 scope.
    ///
    /// A line with a marker, when no scope is open, starts a scope at the brace depth before that
    /// line. The first `{` at or after the marker opens it, and the first `}` that brings the depth
    /// back to that level ends it, on whatever line, so `} else {` ends an `if` scope. Braces in
    /// strings (also in their interpolations) and comments do not count. Every line from the marker
    /// line through the line of the closing brace counts, by the rules of ``codeLines(_:)``.
    ///
    /// This is an upper bound of what a macOS 27 SwiftUI path could delete: the `} else {` line and
    /// code the replacement would still call, such as `LayoutBarMoves.setSection27`, are counted in
    /// favour of adopting.
    public static func scopedLines(_ text: String, markers: [String] = markers) -> Int {
        var commentFree = Masker(text: text, maskStrings: false)
        var codeOnly = Masker(text: text, maskStrings: true)
        let shown = lines(of: commentFree.run())
        let structure = lines(of: codeOnly.run())
        var depth = 0
        var scopeDepth: Int?
        var opened = false
        var total = 0
        for (index, line) in structure.enumerated() {
            if scopeDepth == nil, markers.contains(where: { line.contains($0) }) {
                scopeDepth = depth
                opened = false
            }
            var ended = false
            for character in line {
                if character == "{" {
                    depth += 1
                    if let start = scopeDepth, !opened, depth == start + 1 {
                        opened = true
                    }
                } else if character == "}" {
                    depth -= 1
                    if let start = scopeDepth, opened, depth == start {
                        ended = true
                    }
                }
            }
            if scopeDepth != nil, !shown[index].trimmingCharacters(in: .whitespaces).isEmpty {
                total += 1
            }
            if ended {
                scopeDepth = nil
            }
        }
        return total
    }

    /// The counts of the C1 desk check.
    public struct Report: Equatable, Sendable {
        /// The code lines of all AppKit Layout bar files.
        public let appKitCode: Int

        /// The code lines inside their macOS 27 scopes, an upper bound of what can be deleted.
        public let deletableMax: Int

        /// The code lines of the carried files, a lower bound of what a replacement adds.
        public let newMin: Int

        /// `deletableMax / newMin` rounded to two decimals, `nil` when `newMin` is 0.
        public let ratio: Double?
        public let threshold: Double

        /// Whether the ratio reaches the threshold, `nil` without a ratio.
        public let meets: Bool?
    }

    /// The report for the texts of the AppKit files and of the carried files.
    public static func report(appKit: [String], carried: [String]) -> Report {
        let newMin = carried.reduce(0) { $0 + codeLines($1) }
        let deletableMax = appKit.reduce(0) { $0 + scopedLines($1) }
        let ratio = newMin == 0 ? nil : (Double(deletableMax) / Double(newMin) * 100).rounded() / 100
        return Report(
            appKitCode: appKit.reduce(0) { $0 + codeLines($1) },
            deletableMax: deletableMax,
            newMin: newMin,
            ratio: ratio,
            threshold: threshold,
            meets: ratio.map { $0 >= threshold }
        )
    }

    private static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}

/// Copies Swift source with every comment, and with `maskStrings` also every string's content
/// (interpolations included), replaced by spaces. Newlines stay, so lines keep their numbers.
private struct Masker {
    private let characters: [Character]
    private let maskStrings: Bool
    private var index = 0
    private var output = [Character]()

    init(text: String, maskStrings: Bool) {
        characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        self.maskStrings = maskStrings
    }

    mutating func run() -> String {
        scanCode(masking: false, insideInterpolation: false)
        return String(output)
    }

    private func peek(_ offset: Int) -> Character? {
        let position = index + offset
        return characters.indices.contains(position) ? characters[position] : nil
    }

    private mutating func emit(_ character: Character, masked: Bool) {
        output.append(masked && character != "\n" ? " " : character)
        index += 1
    }

    /// Scans code up to the end of the text, or in an interpolation up to its closing parenthesis
    /// (which is left for the caller).
    private mutating func scanCode(masking: Bool, insideInterpolation: Bool) {
        var parentheses = 0
        while index < characters.count {
            let character = characters[index]
            if character == "/", peek(1) == "/" {
                while index < characters.count, characters[index] != "\n" {
                    emit(characters[index], masked: true)
                }
            } else if character == "/", peek(1) == "*" {
                scanBlockComment()
            } else if character == "\"" {
                scanString(masking: masking)
            } else {
                if insideInterpolation {
                    if character == "(" {
                        parentheses += 1
                    } else if character == ")" {
                        if parentheses == 0 {
                            return
                        }
                        parentheses -= 1
                    }
                }
                emit(character, masked: masking)
            }
        }
    }

    /// A block comment, which Swift lets nest.
    private mutating func scanBlockComment() {
        var depth = 0
        while index < characters.count {
            if characters[index] == "/", peek(1) == "*" {
                depth += 1
                emit("/", masked: true)
                emit("*", masked: true)
            } else if characters[index] == "*", peek(1) == "/" {
                depth -= 1
                emit("*", masked: true)
                emit("/", masked: true)
                if depth == 0 {
                    return
                }
            } else {
                emit(characters[index], masked: true)
            }
        }
    }

    /// A string literal, one line (`"…"`) or several (`"""…"""`), at its opening quote.
    private mutating func scanString(masking: Bool) {
        let multiline = peek(1) == "\"" && peek(2) == "\""
        let hide = masking || maskStrings
        for _ in 0..<(multiline ? 3 : 1) {
            emit("\"", masked: false)
        }
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                if peek(1) == "(" {
                    emit("\\", masked: hide)
                    emit("(", masked: hide)
                    scanCode(masking: hide, insideInterpolation: true)
                    if index < characters.count {
                        emit(")", masked: hide)
                    }
                } else {
                    emit("\\", masked: hide)
                    if index < characters.count {
                        emit(characters[index], masked: hide)
                    }
                }
            } else if character == "\"", !multiline || (peek(1) == "\"" && peek(2) == "\"") {
                for _ in 0..<(multiline ? 3 : 1) {
                    emit("\"", masked: false)
                }
                return
            } else if character == "\n", !multiline {
                return
            } else {
                emit(character, masked: hide)
            }
        }
    }
}
