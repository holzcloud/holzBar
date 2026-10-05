//
//  SourcePIDCache.swift
//  Shared
//

@preconcurrency import ApplicationServices
import Cocoa
import OSLog

/// A cache for the source process identifiers for menu bar item windows.
///
/// We use the term "source process" to refer to the process that created
/// a menu bar item. Originally, we used the CGWindowList API to get the
/// window's owning process (`kCGWindowOwnerPID`), which was always the
/// source process. However, as of macOS 26, item windows are owned by
/// the Control Center.
///
/// We can find what we need using the Accessibility API, but doing it
/// efficiently ends up being a fairly complex process:
///
/// - Accessibility calls block their thread, so the cache is an actor whose
///   executor is its own serial dispatch queue. Scans never run on the main
///   thread or on the Swift concurrency pool.
/// - A scan asks holzBar's own process too (its group and spacer items), and
///   AppKit answers that on the main thread. Callers on the main actor must
///   therefore be suspended, not blocked: holzBar 0.0.6 waited synchronously
///   for such a lookup, both sides waited until Accessibility gave up, and the
///   layout settings and the Shelf stayed on "Loading menu bar items…".
/// - Earlier versions ran this lookup in a helper process nested in the app
///   bundle. Code nested in the bundle runs with holzBar's Accessibility and
///   Screen Recording permission and could be swapped in a copy of the app,
///   so holzBar ships none.
/// - One app that answers slowly must not stall every item read, so a scan is
///   bounded in time (``SourcePIDLookupSchedule``): every element waits 0.5 s
///   at most, a lookup stops asking after 2 s or when its task is cancelled, at
///   most 64 items are read from one app, and an app that ran into the timeout
///   is paused for 10 s, doubling up to 60 s. An item whose app could not be
///   asked in time stays without its app until a later read, and SectionRestore
///   never places such an item.
actor SourcePIDCache {
    /// An object that contains a running application and provides an
    /// interface to access relevant information, such as its process
    /// identifier and extras menu bar.
    nonisolated private final class CachedApplication {
        private let runningApp: NSRunningApplication
        private var extrasMenuBar: AXUIElement?

        /// The app's process identifier.
        var processIdentifier: pid_t {
            runningApp.processIdentifier
        }

        /// A Boolean value indicating whether the app's extras menu
        /// bar has been successfully created and stored.
        var hasExtrasMenuBar: Bool {
            extrasMenuBar != nil
        }

        /// A Boolean value indicating whether the app has terminated.
        var isTerminated: Bool {
            runningApp.isTerminated
        }

        /// A Boolean value indicating whether the app may not have a user
        /// interface, and so has no items to ask about.
        var isProhibited: Bool {
            runningApp.activationPolicy == .prohibited
        }

        /// A Boolean value indicating whether the app is in a valid
        /// state for making accessibility calls.
        var isValidForAccessibility: Bool {
            // These checks help prevent blocking that can occur when
            // calling AX APIs while the app is an invalid state.
            runningApp.isFinishedLaunching &&
            !runningApp.isTerminated &&
            runningApp.activationPolicy != .prohibited &&
            !Bridging.isProcessUnresponsive(processIdentifier)
        }

        /// Creates a `CachedApplication` instance with the given running
        /// application.
        init(_ runningApp: NSRunningApplication) {
            self.runningApp = runningApp
        }

        /// Returns the accessibility element representing the app's extras
        /// menu bar, creating it if necessary.
        ///
        /// When the element is first created, it gets stored for efficient
        /// access on subsequent calls. Both the app's element and the bar wait
        /// ``SourcePIDLookupSchedule/messagingTimeout`` at most for an answer.
        /// The caller checks ``isValidForAccessibility`` first, also before a
        /// stored bar is used again.
        func getOrCreateExtrasMenuBar() -> AXUIElement? {
            if let extrasMenuBar {
                return extrasMenuBar
            }
            guard
                let app = AXHelpers.application(for: runningApp, messagingTimeout: SourcePIDLookupSchedule.messagingTimeout),
                let bar = AXHelpers.extrasMenuBar(for: app)
            else {
                return nil
            }
            AXHelpers.setMessagingTimeout(SourcePIDLookupSchedule.messagingTimeout, for: bar)
            extrasMenuBar = bar
            return bar
        }
    }

    /// A finished scan that did not find a window's source process.
    nonisolated private struct FailedLookup {
        /// When the scan failed.
        let failedAt: ContinuousClock.Instant
        /// The apps the scan skipped because they were launching, unresponsive or
        /// paused. One of them may own the window once it can be asked, which does
        /// not change the running applications.
        let skippedApps: [CachedApplication]
    }

    /// The outcome of one scan over the running apps.
    nonisolated private struct Scan {
        /// The source process of each window found.
        var found = [CGWindowID: pid_t]()
        /// Whether every app was asked or skipped, rather than the scan running out
        /// of time or being cancelled.
        var isFinished = true
        /// The apps the scan could not ask.
        var skippedApps = [CachedApplication]()
    }

    /// The shared cache.
    nonisolated static let shared = SourcePIDCache()

    /// The queue that runs the cache, and with it every blocking Accessibility call
    /// of a scan.
    private let queue: DispatchSerialQueue

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private let logger = Logger(category: "SourcePIDCache")

    private var apps = [CachedApplication]()

    private var pids = [CGWindowID: pid_t]()

    /// Windows whose source process a finished scan did not find. A miss is not
    /// scanned again for ``SourcePIDLookupSchedule/failedLookupInterval``, or until
    /// an app the scan skipped can be asked: every scan asks every running app
    /// through Accessibility (jordanbaird/Ice#911). Starts empty whenever the
    /// running applications change, as a new app may own the window.
    private var failedLookups = [CGWindowID: FailedLookup]()

    /// Which apps ran into the timeout, and until when they are not asked.
    private var schedule = SourcePIDLookupSchedule()

    /// Observer for running applications.
    private var observation: NSKeyValueObservation?

    /// Creates the shared cache.
    private init() {
        queue = DispatchSerialQueue(label: "com.holzcloud.holzBar.SourcePIDCache", qos: .userInitiated)
        Bridging.setProcessUnresponsiveTimeout(3)
    }

    /// Starts the observers for the cache.
    func start() {
        guard observation == nil else {
            return
        }
        logger.debug("Starting observers for source PID cache")
        // AppKit delivers the change on the main thread. The handler only hands it to
        // the cache's queue: it must never wait there while a scan asks holzBar itself.
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { @Sendable [weak self] _, _ in
            Task {
                await self?.runningApplicationsDidChange()
            }
        }
        runningApplicationsDidChange()
    }

    /// Brings the cache in line with the running applications.
    ///
    /// Reads the running applications itself, which AppKit allows from any thread, so
    /// the order in which the observer's tasks arrive does not matter.
    private func runningApplicationsDidChange() {
        logger.debug("Received new running applications")

        let runningApps = NSWorkspace.shared.runningApplications
        let windowIDs = Bridging.getMenuBarWindowList(option: .itemsOnly)
        let runningPIDs = Set(runningApps.map(\.processIdentifier))

        // Prefer the cached apps, as they may have already done the work to
        // initialize their extras menu bars.
        let cachedApps = Dictionary(apps.map { ($0.processIdentifier, $0) }) { first, _ in first }
        apps = runningApps.map { cachedApps[$0.processIdentifier] ?? CachedApplication($0) }
        pids = windowIDs.reduce(into: [:]) { result, windowID in
            if let pid = pids[windowID], runningPIDs.contains(pid) {
                result[windowID] = pid
            }
        }
        failedLookups.removeAll()
        schedule.retain(running: runningPIDs)
    }

    /// Returns the centres of the given windows once their bounds are stable
    /// (a.k.a. not currently changing), by window.
    ///
    /// Reads all windows in up to five rounds and blocks for at most 150 ms in
    /// total. A window whose bounds cannot be read (it probably doesn't exist
    /// anymore) or never settle is left out.
    private func stableCenters(of windows: [WindowInfo]) -> [CGWindowID: CGPoint] {
        var previous = Dictionary(windows.map { ($0.windowID, $0.bounds) }) { first, _ in first }
        var stable = [CGWindowID: CGPoint]()
        for n in 1...5 {
            for (windowID, bounds) in previous {
                guard let current = Bridging.getWindowBounds(for: windowID) else {
                    previous[windowID] = nil
                    continue
                }
                if current == bounds {
                    stable[windowID] = current.center
                    previous[windowID] = nil
                } else {
                    previous[windowID] = current
                }
            }
            if previous.isEmpty || n == 5 {
                break
            }
            // Compute the sleep interval from the current attempt.
            Thread.sleep(forTimeInterval: TimeInterval(n) / 100)
        }
        return stable
    }

    /// Reorders the cached apps so that those that are confirmed
    /// to have an extras menu bar are first in the array.
    private func partitionApps() {
        apps = apps.filter(\.hasExtrasMenuBar) + apps.filter { !$0.hasExtrasMenuBar }
    }

    /// Makes the given Accessibility call and tells whether it ran into the
    /// messaging timeout (``SourcePIDLookupSchedule/didTimeOut(after:)``).
    private func timed<Value>(_ call: () -> Value) -> (value: Value, timedOut: Bool) {
        let start = ContinuousClock.now
        let value = call()
        return (value, SourcePIDLookupSchedule.didTimeOut(after: start.duration(to: .now)))
    }

    /// Records that the app with the given process ran into the timeout.
    private func recordTimeout(of app: CachedApplication, in scan: inout Scan) {
        schedule.record(app.processIdentifier, timedOut: true, at: .now)
        scan.skippedApps.append(app)
        logger.debug("Pausing source PID lookups of process \(app.processIdentifier, privacy: .private) after a timeout")
    }

    /// Asks the running apps which of their items sit at the given window centres.
    ///
    /// The scan stops early, as not finished, once ``SourcePIDLookupSchedule/lookupBudget``
    /// is used up or the calling task is cancelled.
    private func scan(for centers: [CGWindowID: CGPoint]) -> Scan {
        let start = ContinuousClock.now
        var scan = Scan()
        var remaining = centers

        partitionApps()

        appLoop: for app in apps where !remaining.isEmpty {
            let now = ContinuousClock.now
            if Task.isCancelled || SourcePIDLookupSchedule.isOverBudget(startedAt: start, now: now) {
                scan.isFinished = false
                break
            }
            guard !app.isTerminated, !app.isProhibited else {
                continue
            }
            let pid = app.processIdentifier
            guard schedule.mayAsk(pid, at: now), app.isValidForAccessibility else {
                scan.skippedApps.append(app)
                continue
            }
            let bar = timed { app.getOrCreateExtrasMenuBar() }
            if bar.timedOut {
                recordTimeout(of: app, in: &scan)
                continue
            }
            guard let extrasMenuBar = bar.value else {
                schedule.record(pid, timedOut: false, at: .now)
                continue
            }
            let children = timed { AXHelpers.children(for: extrasMenuBar) }
            if children.timedOut {
                recordTimeout(of: app, in: &scan)
                continue
            }
            var timedOut = false
            for child in children.value.prefix(SourcePIDLookupSchedule.maximumChildren) {
                if Task.isCancelled || SourcePIDLookupSchedule.isOverBudget(startedAt: start, now: .now) {
                    scan.isFinished = false
                    break appLoop
                }
                AXHelpers.setMessagingTimeout(SourcePIDLookupSchedule.messagingTimeout, for: child)
                // The frame first: `isEnabled` is only read for an item at a window's
                // centre, which gives the same result with about half the calls.
                let frame = timed { AXHelpers.frame(for: child) }
                if frame.timedOut {
                    timedOut = true
                    break
                }
                guard let childFrame = frame.value else {
                    continue
                }
                let matches = remaining.filter { childFrame.center.distance(to: $0.value) <= 1 }.keys
                guard !matches.isEmpty else {
                    continue
                }
                let enabled = timed { AXHelpers.isEnabled(child) }
                if enabled.timedOut {
                    timedOut = true
                    break
                }
                guard enabled.value else {
                    continue
                }
                for windowID in matches {
                    scan.found[windowID] = pid
                    remaining[windowID] = nil
                }
            }
            if timedOut {
                recordTimeout(of: app, in: &scan)
            } else {
                schedule.record(pid, timedOut: false, at: .now)
            }
        }

        logger.debug("Source PID scan found \(scan.found.count, privacy: .public) of \(centers.count, privacy: .public) windows, finished: \(scan.isFinished, privacy: .public), in \(start.duration(to: .now), privacy: .public)")
        return scan
    }

    /// Returns the source process of each of the given windows that is cached or
    /// found, updating the cache if needed.
    ///
    /// All windows that are not cached are looked up in one scan. A window that a
    /// finished scan did not find is recorded as a miss; a scan that could not run
    /// (no permission, bounds still changing) or that ran out of time or was
    /// cancelled records none, so the next read tries again.
    ///
    /// Starts the cache if nothing has yet, so an item read before the backend's
    /// setup still works.
    func pids(for windows: [WindowInfo]) -> [CGWindowID: pid_t] {
        if observation == nil {
            start()
        }
        dispatchPrecondition(condition: .onQueue(queue))

        let now = ContinuousClock.now
        var result = [CGWindowID: pid_t]()
        var pending = [WindowInfo]()

        // Whether an app a failed scan skipped can be asked now, checked once per app.
        var readiness = [pid_t: Bool]()
        func isReady(_ app: CachedApplication) -> Bool {
            if let ready = readiness[app.processIdentifier] {
                return ready
            }
            let ready = app.isValidForAccessibility && schedule.mayAsk(app.processIdentifier, at: now)
            readiness[app.processIdentifier] = ready
            return ready
        }

        for window in windows {
            if let pid = pids[window.windowID] {
                result[window.windowID] = pid
            } else if
                let failure = failedLookups[window.windowID],
                !SourcePIDLookupSchedule.shouldRescan(
                    failedAt: failure.failedAt,
                    now: now,
                    skippedAppIsReady: failure.skippedApps.contains(where: isReady)
                )
            {
                continue
            } else {
                pending.append(window)
            }
        }

        guard !pending.isEmpty, AXHelpers.isProcessTrusted() else {
            return result
        }
        let centers = stableCenters(of: pending)
        guard !centers.isEmpty else {
            return result
        }

        let scan = scan(for: centers)
        for windowID in centers.keys {
            if let pid = scan.found[windowID] {
                pids[windowID] = pid
                result[windowID] = pid
                failedLookups[windowID] = nil
            } else if scan.isFinished {
                failedLookups[windowID] = FailedLookup(failedAt: now, skippedApps: scan.skippedApps)
            }
        }
        return result
    }
}
