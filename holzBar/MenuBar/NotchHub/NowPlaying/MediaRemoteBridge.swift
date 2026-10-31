//
//  MediaRemoteBridge.swift
//  holzBar
//

import Foundation
import OSLog
import Security

/// Starts Apple's perl with holzBar's own helper framework and hands its output lines on: the
/// wrapper of the one named private-API exception of the Now Playing module's "Read all apps"
/// (CLAUDE.md, "Private API in modules").
///
/// It is the only file that starts a process and names the path of perl, and it does so only
/// while the Notch hub is open (the runtime starts and stops it). perl, an Apple platform binary
/// that macOS still lets use the private MediaRemote framework, loads the helper
/// (`Contents/Frameworks/NowPlayingRemote.framework`) and calls one exported function; the
/// helper prints the playback state, one JSON line at a time, and ends with its parent. This file
/// names no private API: only the helper does.
///
/// The process is configured only from ``NowPlayingRemoteLaunch``: the script is a constant, the
/// function comes from a closed set, the helper's path must lie inside holzBar's own bundle, the
/// environment is two fixed variables, standard input and error are the null device and there is
/// no shell. Before the first start of a session the app bundle, nested code included, is
/// validated statically and without network access, so a copy with a swapped helper is refused.
/// The output is read here, line by line, up to a limit per line. Nothing is written or logged
/// besides that it started or ended, with the exit status as a number.
@MainActor
final class MediaRemoteBridge {
    /// The platform binary that runs the helper.
    private static let perlPath = "/usr/bin/perl"

    /// Called with each complete line of the helper's output.
    var onLine: (@MainActor (String) -> Void)?

    /// Called when the process ended by itself, with its exit status. Not called after ``stop()``.
    var onExit: (@MainActor (Int32) -> Void)?

    /// Called when the route cannot be used at all: the bundle failed its check, the helper is
    /// missing or its path unacceptable, the process could not start, or a line was too long.
    var onUnusable: (@MainActor () -> Void)?

    private var process: Process?
    private var startTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var generation = 0
    private var bundleIsIntact: Bool?
    private let logger = Logger(category: "NowPlayingRemote")

    /// Whether a start is under way or the process runs.
    var isActive: Bool {
        startTask != nil || process != nil
    }

    /// Starts the route unless it is active: checks the bundle once, then starts the process.
    func start() {
        guard !isActive else {
            return
        }
        generation += 1
        let run = generation
        startTask = Task { [weak self] in
            await self?.launch(run: run)
        }
    }

    /// Ends the route: the process is terminated and nothing it still prints is delivered.
    func stop() {
        generation += 1
        startTask?.cancel()
        startTask = nil
        readTask?.cancel()
        readTask = nil
        if let process {
            if process.isRunning {
                process.terminate()
            }
            self.process = nil
            logger.info("The helper was stopped")
        }
    }

    // MARK: Start

    private func launch(run: Int) async {
        defer {
            if run == generation {
                startTask = nil
            }
        }
        let bundleURL = Bundle.main.bundleURL
        let intact: Bool
        if let known = bundleIsIntact {
            intact = known
        } else {
            intact = await Self.bundleCheck(at: bundleURL)
            guard run == generation else {
                return
            }
            bundleIsIntact = intact
        }
        guard intact else {
            logger.notice("The app failed its signature check, so the helper is not started")
            onUnusable?()
            return
        }
        guard let arguments = Self.arguments(bundleURL: bundleURL) else {
            logger.notice("The helper was not found in the app")
            onUnusable?()
            return
        }
        spawn(arguments: arguments, run: run)
    }

    /// The arguments for perl to stream the helper's output, or `nil` when the helper's place is
    /// not acceptable.
    ///
    /// The path is built from the app bundle's own Frameworks folder, so it shares the app's path
    /// form (``Bundle`` resolves `/private` and symbolic links differently for a framework it
    /// opens), and names the framework's executable through the link every framework has at its
    /// top level. The link is part of what the signature check seals.
    private static func arguments(bundleURL: URL) -> [String]? {
        guard let frameworks = Bundle.main.privateFrameworksURL else {
            return nil
        }
        let helper = frameworks
            .appending(path: "NowPlayingRemote.framework", directoryHint: .isDirectory)
            .appending(path: NowPlayingRemoteLaunch.executableName, directoryHint: .notDirectory)
        return NowPlayingRemoteLaunch.arguments(
            helperPath: helper.path(percentEncoded: false),
            bundlePath: bundleURL.path(percentEncoded: false),
            function: .stream
        )
    }

    private func spawn(arguments: [String], run: Int) {
        let process = Process()
        process.executableURL = URL(filePath: Self.perlPath)
        process.arguments = arguments
        process.environment = NowPlayingRemoteLaunch.environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let exitSignal = ExitSignal(process: process)
        process.terminationHandler = { finished in
            exitSignal.finish(status: finished.terminationStatus)
        }
        do {
            try process.run()
        } catch {
            logger.notice("The helper could not be started")
            onUnusable?()
            return
        }
        self.process = process
        logger.info("The helper started")
        let handle = pipe.fileHandleForReading
        readTask = Task { [weak self] in
            let result = await Self.pump(handle: handle, exitSignal: exitSignal) { line in
                self?.deliver(line, run: run)
            }
            self?.pumpDidEnd(result, run: run)
        }
    }

    // MARK: Output

    private enum PumpResult: Sendable {
        /// The output ended and the process ended with this status.
        case ended(Int32)
        /// A line passed the limit.
        case lineTooLong
    }

    /// Reads the helper's output off the main actor and hands each complete line on.
    @concurrent
    private nonisolated static func pump(
        handle: FileHandle,
        exitSignal: ExitSignal,
        deliver: @escaping @MainActor @Sendable (String) -> Void
    ) async -> PumpResult {
        var line = [UInt8]()
        do {
            for try await byte in handle.bytes {
                if byte == 0x0A {
                    // A line that is not UTF-8 reaches the parser as text it rejects.
                    let text = String(bytes: line, encoding: .utf8) ?? "{"
                    line.removeAll(keepingCapacity: true)
                    if !text.isEmpty {
                        await deliver(text)
                    }
                } else {
                    line.append(byte)
                    if line.count > NowPlayingRemoteLaunch.maxLineBytes {
                        return .lineTooLong
                    }
                }
            }
        } catch {
            // A read error ends the output like the end of the file does.
        }
        return .ended(await exitSignal.status())
    }

    private func deliver(_ line: String, run: Int) {
        guard run == generation else {
            return
        }
        onLine?(line)
    }

    private func pumpDidEnd(_ result: PumpResult, run: Int) {
        guard run == generation else {
            return
        }
        switch result {
        case .ended(let status):
            process = nil
            readTask = nil
            logger.info("The helper ended with status \(status, privacy: .public)")
            onExit?(status)
        case .lineTooLong:
            logger.notice("The helper printed a line above the limit and was ended")
            stop()
            onUnusable?()
        }
    }

    // MARK: Integrity

    /// Whether the app bundle, nested code included, is validly signed and unchanged: a strict
    /// static validation without network access, off the main actor.
    @concurrent
    private nonisolated static func bundleCheck(at url: URL) async -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return false
        }
        var flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        flags.insert(.noNetworkAccess)
        return SecStaticCodeCheckValidityWithErrors(code, flags, nil, nil) == errSecSuccess
    }
}

/// Tells the reader how the process ended. The termination handler sets it once; the reader
/// asks for it after the output ended and waits when the process has not yet ended. It also holds
/// the process, so the process lives until its end is known.
private nonisolated final class ExitSignal: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var finished: Int32?
    private var waiting: CheckedContinuation<Int32, Never>?

    init(process: Process) {
        self.process = process
    }

    func finish(status: Int32) {
        lock.lock()
        finished = status
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume(returning: status)
    }

    func status() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let finished {
                lock.unlock()
                continuation.resume(returning: finished)
            } else {
                waiting = continuation
                lock.unlock()
            }
        }
    }
}
