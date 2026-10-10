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

    /// Whether the name is a plain file name: no path, nothing hidden, and no character that can
    /// fake an extension or hide itself.
    ///
    /// Besides the control characters, a name may hold no format character (a right-to-left
    /// override turns `x\u{202E}hs.txt` into `xtxt.sh` on screen, a zero-width space is invisible), no
    /// line or paragraph separator, no private-use, surrogate or unassigned scalar. These are the
    /// general categories ``URLPrompt/displayName(_:)`` drops (T-11-L2).
    static func isPlainName(_ name: String) -> Bool {
        guard
            !name.isEmpty,
            name.utf8.count <= 255,
            !name.hasPrefix("."),
            !name.contains("/"),
            !name.unicodeScalars.contains(where: isHiddenOrControl)
        else {
            return false
        }
        return true
    }

    /// Whether a scalar is one a file name must not hold.
    private static func isHiddenOrControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value < 0x20 || scalar.value == 0x7F {
            return true
        }
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
            return true
        default:
            return false
        }
    }

    /// How the file is run, from its name.
    ///
    /// `.scpt` and `.applescript` files run through `/usr/bin/osascript` (SCRIPT-06). A `.scptd`
    /// bundle is a folder, so ``decide(_:approvedHash:)`` refuses it as not a regular file:
    /// no single hash pins the contents of a bundle.
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

/// What holzBar knows of the scripts folder before it lists or runs anything in it. The facts
/// are read from the folder by the caller, without following a link.
nonisolated struct ScriptFolderInfo: Equatable, Sendable {
    var isDirectory: Bool
    var isSymbolicLink: Bool
    var isOwnedByCurrentUser: Bool
    /// The permission bits of the folder, such as `0o700`.
    var mode: UInt16
}

nonisolated extension ScriptGate {
    /// Why the scripts folder itself is refused (T-11-M6).
    enum FolderRefusal: Equatable, Sendable {
        /// The folder is a symbolic link, so it may lead anywhere.
        case symbolicLink
        case notDirectory
        case notOwnedByUser
        /// Group or others can write to the folder, so they can plant or replace files.
        case writableByOthers
    }

    /// Why the scripts folder is refused, or `nil` when it is a folder the user owns that nobody
    /// else can write to. The checks run in the order of the cases above; a link is refused
    /// first, whatever else is true of it.
    static func folderRefusal(_ folder: ScriptFolderInfo) -> FolderRefusal? {
        guard !folder.isSymbolicLink else {
            return .symbolicLink
        }
        guard folder.isDirectory else {
            return .notDirectory
        }
        guard folder.isOwnedByCurrentUser else {
            return .notOwnedByUser
        }
        guard folder.mode & 0o022 == 0 else {
            return .writableByOthers
        }
        return nil
    }

    /// The path to give `lstat` for a folder: the same path without trailing slashes.
    ///
    /// POSIX follows a symbolic link when the path ends in `/`, so `lstat` of `Scripts/` reports
    /// the link's target and never the link. A folder URL made with `directoryHint:
    /// .isDirectory` has such a slash in `path(percentEncoded:)`; without this cut the folder
    /// check could never see a link (T-11-M6). The root path stays `/`.
    static func pathForLinkCheck(_ path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed = trimmed.dropLast()
        }
        return String(trimmed)
    }

    /// The facts of the folder at `path`, read with `lstat` so a link is reported as a link and
    /// not as the folder it leads to, or `nil` when nothing can be read there.
    static func folderInfo(atPath path: String) -> ScriptFolderInfo? {
        var status = stat()
        guard lstat(pathForLinkCheck(path), &status) == 0 else {
            return nil
        }
        return ScriptFolderInfo(
            isDirectory: status.st_mode & S_IFMT == S_IFDIR,
            isSymbolicLink: status.st_mode & S_IFMT == S_IFLNK,
            isOwnedByCurrentUser: status.st_uid == getuid(),
            mode: UInt16(status.st_mode & 0o7777)
        )
    }
}

/// Limits how often scripts run, over all of them.
///
/// Time is a monotonic instant, not the wall clock: setting the clock back (by hand, by NTP or
/// after a virtual machine resumed) must neither block every script until the clock catches up
/// nor free the limit early (WR-09).
nonisolated struct ScriptRateLimiter: Equatable, Sendable {
    /// The most runs in the window.
    static let maximumRuns = 10
    /// The length of the window, in seconds.
    static let window: TimeInterval = 60

    private var runs: [ContinuousClock.Instant] = []

    /// Records a run and returns `true`, or returns `false` when the limit is reached.
    mutating func allowRun(at now: ContinuousClock.Instant) -> Bool {
        runs.removeAll { now - $0 >= .seconds(Self.window) }
        guard runs.count < Self.maximumRuns else {
            return false
        }
        runs.append(now)
        return true
    }
}

/// The limits on how often scripts run: ten condition checks a minute and, separately, ten
/// runs a minute for everything else (start and end scripts, profile hooks). Checks run on
/// every power, network, app and display event, so with one shared limit a burst of checks
/// could silently starve the start or end script of a rule (WR-08).
nonisolated struct ScriptRunLimiter: Equatable, Sendable {
    private var checks = ScriptRateLimiter()
    private var actions = ScriptRateLimiter()

    /// Records a run of the event's kind and returns `true`, or `false` when that kind has
    /// reached its limit.
    mutating func allowRun(for event: ScriptEvent, at now: ContinuousClock.Instant) -> Bool {
        switch event {
        case .check: checks.allowRun(at: now)
        case .ruleStarted, .ruleEnded, .profileWillApply, .profileDidApply: actions.allowRun(at: now)
        }
    }
}
