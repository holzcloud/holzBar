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
/// beyond the name of the event. A run ends after its time limit (10 seconds unless set, at
/// most 60): the script gets SIGTERM, and SIGKILL two seconds later, sent to the script's
/// whole process group when it leads its own, so what it forked goes too. At most ten runs
/// start a minute, and the script's input and output are discarded.
/// It runs as the user, with holzBar's permissions; macOS asks separately before a script
/// controls another app.
@MainActor
final class ScriptRunner {
    private let logger = Logger(category: "ScriptRunner")
    private var limiter = ScriptRateLimiter()
    private var runningNames = Set<String>()

    /// What the time-limit task tells the run: it fired and signalled the script.
    private final class RunState {
        var didTimeOut = false
    }

    /// Runs the script with the given name once.
    ///
    /// - Parameters:
    ///   - name: The file name in the scripts folder.
    ///   - event: What happened. The only context the script gets.
    ///   - timeLimit: The script's time limit in seconds; it is clamped to 1 through 60.
    ///   - folder: The scripts folder, which is also the script's working directory.
    ///   - store: The store that reads the file and knows the approval.
    func run(
        _ name: String,
        event: ScriptEvent,
        timeLimit: Int,
        folder: URL,
        store: ScriptStore
    ) async -> ScriptOutcome {
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
        guard
            let plan = ScriptLaunchPlan.make(
                fileName: name,
                kind: kind,
                folderPath: folder.path(percentEncoded: false),
                homePath: NSHomeDirectory(),
                event: event
            )
        else {
            logger.notice("A script is not allowed to run")
            return .notAllowed
        }
        runningNames.insert(name)
        defer {
            runningNames.remove(name)
        }
        // The process is configured only from the plan: nothing else reaches the script.
        let process = Process()
        process.executableURL = URL(filePath: plan.executablePath)
        process.arguments = plan.arguments
        process.environment = plan.environment
        process.currentDirectoryURL = URL(filePath: plan.workingDirectoryPath, directoryHint: .isDirectory)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let state = RunState()
        let seconds = ScriptLimits.timeLimit(timeLimit)
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
            // The child leads its own process group, so the group's signals reach what it
            // forked; they must never reach holzBar's own group (measured, design 7.1).
            let pid = process.processIdentifier
            let group = getpgid(pid)
            let leadsOwnGroup = group == pid && group != getpgrp()
            // After the time limit the script gets SIGTERM, and SIGKILL two seconds later.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                guard process.isRunning else {
                    return
                }
                state.didTimeOut = true
                if leadsOwnGroup {
                    killpg(pid, SIGTERM)
                } else {
                    kill(pid, SIGTERM)
                }
                try? await Task.sleep(for: .seconds(ScriptLimits.killGraceSeconds))
                if leadsOwnGroup {
                    // The group may hold children that outlive the leader.
                    killpg(pid, SIGKILL)
                } else if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }
        logger.notice("A script ended with status \(status, privacy: .public)")
        // A script that ends with status 0 after it was signalled still timed out.
        return status == 0 && !state.didTimeOut ? .succeeded : .failed
    }
}
