//
//  ScriptRunner.swift
//  holzBar
//

import Foundation
import OSLog

/// What came of a run.
enum ScriptOutcome: Equatable {
    /// The script ended with status 0.
    case succeeded
    /// It ended with another status, or did not end in time.
    case failed
    /// The gate refused it, or it needs the user's approval first.
    case notAllowed
    /// Too many runs in the last minute.
    case rateLimited
}

/// Runs the scripts the user approved.
///
/// Nothing but the gate's decision lets a script run: the file is checked again just before
/// each run, from the Scripts folder only, with no shell, no arguments and no data from holzBar
/// beyond the name of the event. A run ends after ten seconds (SIGTERM, then SIGKILL after two
/// more), at most ten runs start a minute, and the script's input and output are discarded.
/// It runs as the user, with holzBar's permissions; macOS asks separately before a script
/// controls another app.
@MainActor
final class ScriptRunner {
    private let logger = Logger(category: "ScriptRunner")
    private var limiter = ScriptRateLimiter()
    private var runningNames = Set<String>()

    /// The longest a script may run, in seconds.
    private static let timeLimit = 10.0

    /// Runs the script with the given name once.
    ///
    /// - Parameters:
    ///   - name: The file name in the Scripts folder.
    ///   - event: What the rule did: `rule-started`, `rule-ended` or `check`.
    func run(_ name: String, event: String, store: ScriptStore) async -> ScriptOutcome {
        guard !runningNames.contains(name) else {
            return .failed
        }
        guard
            let info = store.fileInfo(for: name),
            case .allowed(let kind) = ScriptGate.decide(info, approvedHash: store.approvedHash(for: name))
        else {
            logger.notice("A script is not allowed to run")
            return .notAllowed
        }
        guard limiter.allowRun(at: .now) else {
            logger.notice("Too many script runs; one was skipped")
            return .rateLimited
        }
        runningNames.insert(name)
        defer {
            runningNames.remove(name)
        }
        let path = ScriptStore.folder.appending(path: name, directoryHint: .notDirectory).path(percentEncoded: false)
        let process = Process()
        switch kind {
        case .executable:
            process.executableURL = URL(filePath: path)
            process.arguments = []
        case .appleScript:
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = [path]
        }
        process.currentDirectoryURL = ScriptStore.folder
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
            "HOLZBAR_EVENT": event,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let status: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
                return
            }
            // After the time limit the script gets SIGTERM, and SIGKILL two seconds later.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.timeLimit))
                guard process.isRunning else {
                    return
                }
                process.terminate()
                try? await Task.sleep(for: .seconds(2))
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        logger.notice("A script ended with status \(status, privacy: .public)")
        return status == 0 ? .succeeded : .failed
    }
}
