//
//  ApplicationMenuFrames.swift
//  holzBar
//

import Cocoa
import Observation
import OSLog
import os

/// The frame of the application menu on each display, read off the main thread.
///
/// Show on click and hover, the secondary context menu, hiding application menus,
/// temporarily shown items and the menu bar overlay all need to know where the frontmost
/// application's menus end. Reading that asks the application through Accessibility,
/// which blocks until it answers. holzBar used to read it on the main thread, where its
/// event monitors and the click tap of macOS 27 wait too, so a hung application froze
/// every click on the Mac. Now it is read on a queue of its own, with a short messaging
/// timeout, when something that can change it happens; everything else reads the cache.
@MainActor
@Observable
final class ApplicationMenuFrames {
    /// The frame of the application menu on each display; a missing entry means there is none.
    private(set) var frames = [CGDirectDisplayID: CGRect]()

    /// The displays whose menu bar window is a menu bar Accessibility can reach. The menu
    /// bar overlay draws only there (see `MenuBarManager.hasValidMenuBar(in:for:)`).
    private(set) var validMenuBars = Set<CGDirectDisplayID>()

    /// The queue that reads the frames. Accessibility calls block, so they never run on
    /// the main thread or in the Swift concurrency pool.
    @ObservationIgnored private let queue = DispatchQueue(
        label: "com.holzcloud.holzBar.ApplicationMenuFrames",
        qos: .userInitiated
    )

    /// The number of the latest read. A read that a newer one replaced is dropped.
    @ObservationIgnored private let latestGeneration = OSAllocatedUnfairLock(initialState: 0)

    /// The reads that follow a change once more, for applications that draw their menus late.
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// Tasks that observe notifications, kept while the cache exists.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Key-value observers of the workspace.
    @ObservationIgnored private var keyValueObservations = [NSKeyValueObservation]()

    @ObservationIgnored private let logger = Logger(category: "ApplicationMenuFrames")

    /// When the follow-up reads run after a change, counted from the change: an application
    /// that has just become frontmost may build its menus a moment later.
    private static let settleReads: [Duration] = [.milliseconds(150), .milliseconds(600)]

    deinit {
        for task in observerTasks {
            task.cancel()
        }
        settleTask?.cancel()
    }

    /// Starts following the events that can change the application menu, and reads it.
    func performSetup() {
        keyValueObservations.append(
            NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refresh(reason: "frontmost application changed")
                }
            }
        )
        keyValueObservations.append(
            NSWorkspace.shared.observe(\.menuBarOwningApplication, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.refresh(reason: "menu bar owner changed")
                }
            }
        )
        observerTasks.append(Task { [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                self?.refresh(reason: "active space changed")
            }
        })
        observerTasks.append(Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.refresh(reason: "screens changed")
            }
        })
        refresh(reason: "setup")
    }

    /// The frame of the application menu on the given screen, from the last read.
    ///
    /// It never asks another application, so it is safe on any input path.
    func frame(for screen: NSScreen) -> CGRect? {
        frames[screen.displayID]
    }

    /// Whether the menu bar window of the given display was a menu bar at the last read.
    ///
    /// It never asks another application, so it is safe on the main thread.
    func hasValidMenuBar(on displayID: CGDirectDisplayID) -> Bool {
        validMenuBars.contains(displayID)
    }

    /// Reads the frames now and, unless `settling` is `false`, twice more shortly after
    /// (150 ms and 600 ms), then stops. A refresh replaces the one that is still running.
    ///
    /// - Parameters:
    ///   - reason: What changed, for the debug log.
    ///   - settling: Whether the follow-up reads run.
    func refresh(reason: String, settling: Bool = true) {
        logger.debug("Refreshing application menu frames: \(reason, privacy: .public)")
        settleTask?.cancel()
        settleTask = nil
        read()
        guard settling else {
            return
        }
        settleTask = Task { [weak self] in
            var elapsed = Duration.zero
            for delay in Self.settleReads {
                do {
                    try await Task.sleep(for: delay - elapsed)
                } catch {
                    return
                }
                elapsed = delay
                self?.read()
            }
        }
    }

    /// Reads the frame on every screen on the queue and publishes the result on the main actor.
    private func read() {
        let queries = NSScreen.screens.map(\.applicationMenuQuery)
        let generation = latestGeneration.withLock { value in
            value += 1
            return value
        }
        Task { [weak self, queue, latestGeneration] in
            guard let result = await Self.readFrames(
                queries,
                generation: generation,
                latestGeneration: latestGeneration,
                on: queue
            ) else {
                return
            }
            self?.publish(result, generation: generation)
        }
    }

    /// Reads the frames on the given queue, or returns `nil` when a newer read started first.
    private nonisolated static func readFrames(
        _ queries: [ApplicationMenuQuery],
        generation: Int,
        latestGeneration: OSAllocatedUnfairLock<Int>,
        on queue: DispatchQueue
    ) async -> ReadResult? {
        await withCheckedContinuation { continuation in
            queue.async {
                var result = ReadResult()
                for query in queries {
                    // A newer read has started; it answers instead.
                    guard latestGeneration.withLock({ $0 }) == generation else {
                        continuation.resume(returning: nil)
                        return
                    }
                    if query.hasValidMenuBar() {
                        result.validMenuBars.insert(query.displayID)
                    }
                    if let frame = query.getApplicationMenuFrame() {
                        result.frames[query.displayID] = frame
                    }
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Stores the result of a read, unless a newer read has started since.
    private func publish(_ result: ReadResult, generation: Int) {
        guard latestGeneration.withLock({ $0 }) == generation else {
            return
        }
        // Stored only when they change: observers redraw on every assignment.
        if result.frames != frames {
            frames = result.frames
        }
        if result.validMenuBars != validMenuBars {
            validMenuBars = result.validMenuBars
        }
    }
}

// MARK: - ReadResult

extension ApplicationMenuFrames {
    /// What one read found on every display.
    private nonisolated struct ReadResult: Sendable {
        var frames = [CGDirectDisplayID: CGRect]()
        var validMenuBars = Set<CGDirectDisplayID>()
    }
}
