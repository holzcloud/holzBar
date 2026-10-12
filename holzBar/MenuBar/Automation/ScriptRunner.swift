//
//  ScriptRunner.swift
//  holzBar
//

import Foundation
import OSLog
import os

/// What came of a run.
enum ScriptOutcome: Equatable {
    /// The script ended with status 0.
    case succeeded
    /// It ended with another status, was ended by a signal, or could not start.
    case failed
    /// It did not end within its time limit and was signalled.
    case timedOut
    /// The script is already running; this run was not started.
    case busy
    /// The gate refused it, or it needs the user's approval first.
    case notAllowed
    /// Too many runs in the last minute.
    case rateLimited
}

extension ScriptSkipReason {
    /// The reason a run did not start, or `nil` when the outcome is not a skipped run.
    init?(outcome: ScriptOutcome) {
        switch outcome {
        case .busy: self = .busy
        case .rateLimited: self = .rateLimited
        case .succeeded, .failed, .timedOut, .notAllowed: return nil
        }
    }
}

/// The result of one call of ``ScriptRunner/run(_:event:timeLimit:folder:store:)``.
struct ScriptRunReport: Equatable {
    let outcome: ScriptOutcome
    /// What the run left behind, for every run that started; `nil` when none did.
    let record: ScriptRunRecord?
}

/// Runs the scripts the user approved.
///
/// Nothing but the gate's decision lets a script run: the file is checked again just before
/// each run, from the Scripts folder only, with no shell, no arguments and no data from holzBar
/// beyond the name of the event. A run ends after its time limit (10 seconds unless set, at
/// most 60): the script gets SIGTERM, and SIGKILL two seconds later, sent to the script's
/// whole process group when it leads its own, so what it forked goes too. At most ten condition
/// checks and ten other runs start a minute. Its input is `/dev/null`; each of its two output
/// streams is read to the end and kept up to 64 KB, the rest is dropped, and only one cleaned
/// line of at most 80 characters is kept, in memory, never logged.
/// It runs as the user, with holzBar's permissions; macOS asks separately before a script
/// controls another app.
@MainActor
final class ScriptRunner {
    private let logger = Logger(category: "ScriptRunner")
    private var limiter = ScriptRunLimiter()
    private var runningNames = Set<String>()

    /// How long the runner waits for the end of the output after the script ended, in
    /// 50 millisecond steps (one second). A background child that keeps a pipe open cannot keep
    /// the run alive longer.
    private static let outputGraceSteps = 20

    /// What the time-limit task tells the run: it fired and signalled the script.
    private final class RunState {
        var didTimeOut = false
    }

    /// How the process ended, as the termination handler saw it.
    private struct ProcessExit: Sendable {
        let status: Int32
        let wasSignaled: Bool
    }

    /// One output stream of the script: a pipe that is always drained, into a buffer that keeps
    /// at most 64 KB.
    ///
    /// A dispatch source reads a duplicate of the pipe's read end and closes it in its cancel
    /// handler, which runs only after the last read. Closing the end while a read handler may
    /// still be running would make `FileHandle.availableData` raise an Objective-C exception,
    /// which Swift cannot catch, when an approved script leaves a background child that keeps
    /// writing past the grace period (WR-06).
    private nonisolated final class OutputCapture: Sendable {
        /// The pipe whose write end goes to the process.
        let pipe = Pipe()
        private let buffer = OSAllocatedUnfairLock(
            initialState: ScriptOutputBuffer(limit: ScriptLimits.maximumOutputBytes)
        )
        private let reachedEnd = OSAllocatedUnfairLock(initialState: false)
        private let source: (any DispatchSourceRead)?

        init() {
            // The source's own descriptor: the pipe's file handle closes its descriptor when it
            // goes away, and a descriptor closed twice may close another file.
            let descriptor = fcntl(pipe.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 0)
            let buffer = buffer
            let reachedEnd = reachedEnd
            guard descriptor >= 0 else {
                source = nil
                reachedEnd.withLock { $0 = true }
                return
            }
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global(qos: .utility))
            source.setEventHandler {
                var chunk = [UInt8](repeating: 0, count: 65_536)
                while true {
                    let count = read(descriptor, &chunk, chunk.count)
                    if count > 0 {
                        let received = Data(chunk[0..<count])
                        buffer.withLock { $0.append(received) }
                    } else if count < 0, errno == EINTR {
                        continue
                    } else if count < 0, errno == EAGAIN {
                        // Everything that was there is read; the source fires again.
                        return
                    } else {
                        // End of file or an error: nothing more will come. The cancel handler
                        // closes the descriptor.
                        reachedEnd.withLock { $0 = true }
                        source.cancel()
                        return
                    }
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            self.source = source
        }

        /// Whether the script closed the stream.
        var isAtEnd: Bool {
            reachedEnd.withLock { $0 }
        }

        /// Stops reading and returns what was kept.
        func finish() -> Data {
            source?.cancel()
            try? pipe.fileHandleForReading.close()
            return buffer.withLock { $0.data }
        }
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
    ) async -> ScriptRunReport {
        guard !runningNames.contains(name) else {
            return ScriptRunReport(outcome: .busy, record: nil)
        }
        guard
            let info = store.fileInfo(for: name),
            case .allowed(let kind) = ScriptGate.decide(info, approvedHash: store.approvedHash(for: name))
        else {
            logger.notice("A script is not allowed to run")
            return ScriptRunReport(outcome: .notAllowed, record: nil)
        }
        guard limiter.allowRun(for: event, at: ContinuousClock.now) else {
            logger.notice("Too many script runs; one was skipped")
            return ScriptRunReport(outcome: .rateLimited, record: nil)
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
            return ScriptRunReport(outcome: .notAllowed, record: nil)
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
        let standardOutput = OutputCapture()
        let standardError = OutputCapture()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutput.pipe
        process.standardError = standardError.pipe

        let state = RunState()
        let seconds = ScriptLimits.timeLimit(timeLimit)
        var watchdog: Task<Void, Never>?
        let exit: ProcessExit? = await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(
                    returning: ProcessExit(
                        status: finished.terminationStatus,
                        wasSignaled: finished.terminationReason == .uncaughtSignal
                    )
                )
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
                return
            }
            // The child leads its own process group, so the group's signals reach what it
            // forked; they must never reach holzBar's own group (measured, design 7.1).
            let pid = process.processIdentifier
            let group = getpgid(pid)
            let leadsOwnGroup = group == pid && group != getpgrp()
            // After the time limit the script gets SIGTERM, and SIGKILL two seconds later.
            watchdog = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, process.isRunning else {
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
        if !state.didTimeOut {
            // It ended before its time limit: nothing is left to signal.
            watchdog?.cancel()
        }
        guard let exit else {
            _ = standardOutput.finish()
            _ = standardError.finish()
            logger.notice("A script could not be started")
            let record = ScriptRunRecord(date: .now, termination: .notLaunched, displayLine: "")
            return ScriptRunReport(outcome: .failed, record: record)
        }

        // The pipes are read to their end, but a background child that keeps one open does not
        // keep the run alive: after a second they are closed with what was read.
        for _ in 0..<Self.outputGraceSteps where !(standardOutput.isAtEnd && standardError.isAtEnd) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let output = standardOutput.finish()
        let errors = standardError.finish()
        var line = ScriptOutput.displayLine(output)
        if line.isEmpty {
            line = ScriptOutput.displayLine(errors)
        }

        let termination: ScriptTermination
        let outcome: ScriptOutcome
        if state.didTimeOut {
            // A script that ends with status 0 after it was signalled still timed out.
            termination = .timedOut
            outcome = .timedOut
            logger.notice("A script exceeded its time limit")
        } else if exit.wasSignaled {
            termination = .signaled(exit.status)
            outcome = .failed
            logger.notice("A script was ended by signal \(exit.status, privacy: .public)")
        } else {
            termination = .exited(exit.status)
            outcome = termination.succeeded ? .succeeded : .failed
            logger.notice("A script ended with status \(exit.status, privacy: .public)")
        }
        let record = ScriptRunRecord(date: .now, termination: termination, displayLine: line)
        return ScriptRunReport(outcome: outcome, record: record)
    }
}
