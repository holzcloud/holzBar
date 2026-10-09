//
//  ScriptGate.swift
//  holzBar
//

import Foundation

/// What holzBar knows of a script file before it may run it. The facts are read from the
/// file by the caller; the decision is made here, as pure logic.
nonisolated struct ScriptFileInfo: Equatable, Sendable {
    /// The file name, without a path.
    var name: String
    var isRegularFile: Bool
    var isSymbolicLink: Bool
    var isOwnedByCurrentUser: Bool
    /// The permission bits of the file, such as `0o755`.
    var mode: UInt16
    var hasQuarantineAttribute: Bool
    var size: Int
    /// The SHA-256 of the contents, in lower-case hexadecimal.
    var sha256: String
}

/// How a script is run.
nonisolated enum ScriptKind: Equatable, Sendable {
    /// An executable file, run directly: its first line decides the interpreter.
    case executable
    /// An AppleScript file, run by `/usr/bin/osascript`.
    case appleScript
}

/// Decides whether a script may run: only a plain file the user owns, that nobody else can
/// write to, that came from no download, that is small, and whose contents the user approved.
/// A script that changed since the approval needs a new one.
nonisolated enum ScriptGate {
    /// The largest script file, in bytes.
    static let maximumSize = 1_000_000

    /// Why a script is refused.
    nonisolated enum Refusal: Equatable, Sendable {
        case badName
        case notRegularFile
        case symbolicLink
        case notOwnedByUser
        case writableByOthers
        case quarantined
        case tooLarge
        case notExecutable
    }

    /// What may happen with a script.
    nonisolated enum Decision: Equatable, Sendable {
        case refused(Refusal)
        /// The file is fine but the user has not approved these contents.
        case needsApproval
        case allowed(ScriptKind)
    }

    /// Whether the name is a plain file name: no path, nothing hidden, no control characters.
    static func isPlainName(_ name: String) -> Bool {
        guard
            !name.isEmpty,
            name.utf8.count <= 255,
            !name.hasPrefix("."),
            !name.contains("/"),
            !name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else {
            return false
        }
        return true
    }

    /// How the file is run, from its name.
    static func kind(forName name: String) -> ScriptKind {
        let lowercased = name.lowercased()
        if lowercased.hasSuffix(".scpt") || lowercased.hasSuffix(".applescript") {
            return .appleScript
        }
        return .executable
    }

    /// The decision for a script file.
    ///
    /// - Parameters:
    ///   - info: The facts read from the file.
    ///   - approvedHash: The SHA-256 the user approved for this file name, if any.
    static func decide(_ info: ScriptFileInfo, approvedHash: String?) -> Decision {
        guard isPlainName(info.name) else {
            return .refused(.badName)
        }
        guard !info.isSymbolicLink else {
            return .refused(.symbolicLink)
        }
        guard info.isRegularFile else {
            return .refused(.notRegularFile)
        }
        guard info.isOwnedByCurrentUser else {
            return .refused(.notOwnedByUser)
        }
        guard info.mode & 0o022 == 0 else {
            return .refused(.writableByOthers)
        }
        guard !info.hasQuarantineAttribute else {
            return .refused(.quarantined)
        }
        guard info.size <= maximumSize else {
            return .refused(.tooLarge)
        }
        let kind = kind(forName: info.name)
        if kind == .executable, info.mode & 0o100 == 0 {
            return .refused(.notExecutable)
        }
        guard let approvedHash, approvedHash == info.sha256 else {
            return .needsApproval
        }
        return .allowed(kind)
    }
}

/// Limits how often scripts run, over all of them.
nonisolated struct ScriptRateLimiter: Equatable, Sendable {
    /// The most runs in the window.
    static let maximumRuns = 10
    /// The length of the window, in seconds.
    static let window: TimeInterval = 60

    private var runs: [Date] = []

    /// Records a run and returns `true`, or returns `false` when the limit is reached.
    mutating func allowRun(at now: Date) -> Bool {
        runs.removeAll { now.timeIntervalSince($0) >= Self.window }
        guard runs.count < Self.maximumRuns else {
            return false
        }
        runs.append(now)
        return true
    }
}
