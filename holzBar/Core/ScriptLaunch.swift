//
//  ScriptLaunch.swift
//  holzBar
//

import Foundation

/// The only context a script gets: what happened, as one of five fixed names in the
/// `HOLZBAR_EVENT` environment variable.
///
/// No value from a rule, a profile, an app, a Wi-Fi network or an item ever reaches a script
/// (D-06, T-11-H3). The raw values are what the script sees; they are part of the feature's
/// contract and never change.
nonisolated enum ScriptEvent: String, CaseIterable, Sendable {
    /// A rule that runs the script became true.
    case ruleStarted = "rule-started"
    /// A rule that runs the script stopped being true and runs it again when it ends.
    case ruleEnded = "rule-ended"
    /// A rule asks the script as a condition.
    case check
    /// A profile is about to be applied (the script is a before hook).
    case profileWillApply = "profile-will-apply"
    /// A profile was applied and the items moved (the script is an after hook).
    case profileDidApply = "profile-did-apply"
}

/// Everything needed to start a script, and nothing else: the program, its arguments, its
/// environment and its working directory. The runner configures its `Process` only from a plan
/// built by ``make(fileName:kind:folderPath:homePath:event:)``.
nonisolated struct ScriptLaunchPlan: Equatable, Sendable {
    /// The program to start: the script itself, or `/usr/bin/osascript` for an AppleScript.
    var executablePath: String
    /// The arguments: none for an executable, the script's own path for an AppleScript.
    var arguments: [String]
    /// The whole environment of the child: `PATH`, `HOME`, `LANG` and `HOLZBAR_EVENT`.
    var environment: [String: String]
    /// The folder the script runs in: the scripts folder.
    var workingDirectoryPath: String

    /// The `PATH` of a script: the system tools only.
    static let searchPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    /// The interpreter of AppleScript files.
    static let osascriptPath = "/usr/bin/osascript"
    /// The `LANG` of a script.
    static let language = "en_US.UTF-8"

    /// The plan for one run, or `nil` when the name is not a plain file name or the folder is
    /// not an absolute path.
    ///
    /// - Parameters:
    ///   - fileName: The file name in the scripts folder.
    ///   - kind: How the file is run.
    ///   - folderPath: The absolute path of the scripts folder.
    ///   - homePath: The user's home folder, for `HOME`.
    ///   - event: What happened.
    static func make(
        fileName: String,
        kind: ScriptKind,
        folderPath: String,
        homePath: String,
        event: ScriptEvent
    ) -> ScriptLaunchPlan? {
        guard ScriptGate.isPlainName(fileName), folderPath.hasPrefix("/") else {
            return nil
        }
        var folder = folderPath
        if folder.count > 1, folder.hasSuffix("/") {
            folder.removeLast()
        }
        let path = folder == "/" ? "/" + fileName : folder + "/" + fileName
        let environment = [
            "PATH": searchPath,
            "HOME": homePath,
            "LANG": language,
            "HOLZBAR_EVENT": event.rawValue,
        ]
        switch kind {
        case .executable:
            return ScriptLaunchPlan(
                executablePath: path,
                arguments: [],
                environment: environment,
                workingDirectoryPath: folder
            )
        case .appleScript:
            return ScriptLaunchPlan(
                executablePath: osascriptPath,
                arguments: [path],
                environment: environment,
                workingDirectoryPath: folder
            )
        }
    }
}

/// The limits of a script run (D-07).
nonisolated enum ScriptLimits {
    /// The time limit when none is set, in seconds.
    static let defaultTimeLimit = 10
    /// The shortest time limit, in seconds.
    static let minimumTimeLimit = 1
    /// The longest time limit, in seconds.
    static let maximumTimeLimit = 60
    /// How long a script gets between SIGTERM and SIGKILL, in seconds.
    static let killGraceSeconds = 2
    /// The most bytes kept of each of stdout and stderr; the rest is read and dropped.
    static let maximumOutputBytes = 65_536

    /// The time limit to use for a stored value: the default when none is stored, otherwise the
    /// value clamped to ``minimumTimeLimit`` through ``maximumTimeLimit``.
    static func timeLimit(_ stored: Int?) -> Int {
        guard let stored else {
            return defaultTimeLimit
        }
        return min(max(stored, minimumTimeLimit), maximumTimeLimit)
    }
}

/// How a run ended.
///
/// A timeout, a signal or a script that did not start is never success: a condition is never
/// true on error (D-04).
nonisolated enum ScriptTermination: Equatable, Sendable {
    /// The script ended by itself with this status.
    case exited(Int32)
    /// The script was ended by this signal.
    case signaled(Int32)
    /// The script exceeded its time limit and was signalled.
    case timedOut
    /// The process could not be started.
    case notLaunched

    /// Whether the script ended by itself with status 0.
    var succeeded: Bool {
        self == .exited(0)
    }
}
