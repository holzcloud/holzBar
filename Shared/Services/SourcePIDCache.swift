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
///   or was asked for 1 s is paused for 10 s, doubling up to 60 s. A scan that
///   stopped early is continued by the next read (``SourcePIDScan``). An item
///   whose app could not be asked yet stays without its app until a later read,
///   and SectionRestore never places such an item.
/// - The frames come from each app itself, so any app could report an item where
///   another app's item is, such as Control Center's camera and microphone indicator.
///   Apps signed by Apple are asked first, and the first of them to claim a window gets
///   it. Any other app gets a window only when a finished scan that skipped no app
///   signed by Apple found no other app claiming it (``SourcePIDClaims``). An app that
///   never finishes launching, such as WebKit's XPC services, is not skipped but left
///   out: it can never be asked.
/// - The item manager reads the bar again for an unchanged window list only while a
///   read could find more (``hasPendingLookups(in:)``), not for a window that no app
///   claims: that read would only repeat the scan.
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

        /// A Boolean value indicating whether the app's code is signed by Apple.
        ///
        /// Read from the code signature once, the first time it is used, on the
        /// cache's queue: the check blocks while it reads the signature.
        private(set) lazy var isSignedByApple = CodeSignature.isSignedByApple(processIdentifier: processIdentifier)

        /// A Boolean value indicating whether the app may not have a user
        /// interface, and so has no items to ask about.
        var isProhibited: Bool {
            runningApp.activationPolicy == .prohibited
        }

        /// When the app's process started, read from the kernel the first time it is
        /// needed, or `nil` if it cannot be read.
        private lazy var processStartDate: Date? = Self.startDate(ofProcess: processIdentifier)

        /// A Boolean value indicating whether the app never finishes launching
        /// (``SourcePIDLookupSchedule/neverFinishesLaunching(isFinishedLaunching:runningFor:)``),
        /// such as WebKit's XPC services. The start time is read only for an app that has
        /// not finished launching.
        var neverFinishesLaunching: Bool {
            guard !runningApp.isFinishedLaunching else {
                return false
            }
            return SourcePIDLookupSchedule.neverFinishesLaunching(
                isFinishedLaunching: false,
                runningFor: processStartDate.map { .seconds(Date.now.timeIntervalSince($0)) }
            )
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

        /// Returns when the process with the given identifier started, from the kernel's
        /// process table, or `nil` if the process does not exist (any more).
        private static func startDate(ofProcess pid: pid_t) -> Date? {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else {
                return nil
            }
            let start = info.kp_proc.p_un.__p_starttime
            return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
        }
    }

    /// A finished scan that did not find a window's source process.
    nonisolated private struct FailedLookup {
        /// When the scan failed.
        let failedAt: ContinuousClock.Instant
        /// The apps the scan skipped because they were launching, unresponsive or
        /// paused, or ran into the timeout. One of them may own the window once it
        /// can be asked, which does not change the running applications. holzBar's
        /// own process is never one of them: it can always be asked.
        let skippedApps: [CachedApplication]
    }

    /// Asks the cached apps through Accessibility, for a scan.
    nonisolated private struct ScanSource: SourcePIDScanSource {
        var now: ContinuousClock.Instant {
            .now
        }

        var isCancelled: Bool {
            Task.isCancelled
        }

        func pid(of app: CachedApplication) -> pid_t {
            app.processIdentifier
        }

        func isSignedByApple(_ app: CachedApplication) -> Bool {
            app.isSignedByApple
        }

        func isValidForAccessibility(_ app: CachedApplication) -> Bool {
            app.isValidForAccessibility
        }

        func neverFinishesLaunching(_ app: CachedApplication) -> Bool {
            app.neverFinishesLaunching
        }

        func extrasMenuBar(of app: CachedApplication) -> AXUIElement? {
            app.getOrCreateExtrasMenuBar()
        }

        func children(of element: AXUIElement) -> [AXUIElement] {
            AXHelpers.children(for: element)
        }

        func frame(of element: AXUIElement) -> CGRect? {
            AXHelpers.setMessagingTimeout(SourcePIDLookupSchedule.messagingTimeout, for: element)
            return AXHelpers.frame(for: element)
        }

        func isEnabled(_ element: AXUIElement) -> Bool {
            AXHelpers.isEnabled(element)
        }
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

    /// Windows without a source process that the next read looks up again: their lookup
    /// could not run (no permission, bounds still changing) or did not finish, or the
    /// running applications changed since it failed.
    private var unsettledWindows = Set<CGWindowID>()

    /// Which apps ran into the timeout, and until when they are not asked.
    private var schedule = SourcePIDLookupSchedule()

    /// The last scan, while it stopped early: the next read continues it rather than
    /// asking the same apps again (``SourcePIDScan/continued(for:at:)``). Starts over
    /// whenever the running applications change.
    private var unfinishedScan: SourcePIDScan<CachedApplication>?

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
        // A terminated app's process identifier may already belong to a new process.
        let cachedApps = Dictionary(apps.lazy.filter { !$0.isTerminated }.map { ($0.processIdentifier, $0) }) { first, _ in first }
        apps = runningApps.map { cachedApps[$0.processIdentifier] ?? CachedApplication($0) }
        pids = windowIDs.reduce(into: [:]) { result, windowID in
            if let pid = pids[windowID], runningPIDs.contains(pid) {
                result[windowID] = pid
            }
        }
        // A new app may own a window that a scan without it missed, so the misses are looked
        // up again, also while the window list stays the same.
        unsettledWindows = unsettledWindows.union(failedLookups.keys).intersection(windowIDs)
        failedLookups.removeAll()
        unfinishedScan = nil
        schedule.retain(running: runningPIDs)
    }

    /// Returns the centres of the given windows once their bounds are stable
    /// (a.k.a. not currently changing), by window.
    ///
    /// Reads all windows in up to five rounds, with at most 100 ms of sleep in
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

    /// Reorders the cached apps: those signed by Apple first, then the others, and in
    /// each group those that are confirmed to have an extras menu bar first. Apps that a
    /// scan leaves out anyway come last, without a signature check.
    private func partitionApps() {
        func group(of app: CachedApplication) -> Int {
            if app.isTerminated || app.isProhibited || app.neverFinishesLaunching {
                return 4
            }
            return (app.isSignedByApple ? 0 : 2) + (app.hasExtrasMenuBar ? 0 : 1)
        }
        let grouped = apps.map { (app: $0, group: group(of: $0)) }
        apps = (0...4).flatMap { group in
            grouped.filter { $0.group == group }.map(\.app)
        }
    }

    /// Asks the running apps which of their items sit at the given window centres,
    /// continuing the last scan if it stopped early.
    ///
    /// The scan stops early, as not finished, once ``SourcePIDLookupSchedule/lookupBudget``
    /// is used up or the calling task is cancelled. The apps' code signatures are read
    /// before, outside the budget.
    private func scan(for centers: [CGWindowID: CGPoint]) -> SourcePIDScan<CachedApplication> {
        let start = ContinuousClock.now
        partitionApps()
        let continued = unfinishedScan?.continued(for: centers, at: start)
        var scan = continued ?? SourcePIDScan(centers: centers, startedAt: start)
        let paused = scan.run(
            over: apps.filter { !$0.isTerminated && !$0.isProhibited },
            with: ScanSource(),
            schedule: &schedule
        )
        unfinishedScan = scan.isFinished ? nil : scan
        for pid in paused {
            logger.debug("Pausing source PID lookups of process \(pid, privacy: .private) after a timeout")
        }

        var found = 0
        var contested = 0
        for windowID in centers.keys {
            switch scan.decision(for: windowID) {
            case .owner: found += 1
            case .contested: contested += 1
            case .unresolved: break
            }
        }
        logger.debug("Source PID scan found \(found, privacy: .public) of \(centers.count, privacy: .public) windows, \(contested, privacy: .public) contested, continued: \(continued != nil, privacy: .public), finished: \(scan.isFinished, privacy: .public), in \(start.duration(to: .now), privacy: .public)")
        return scan
    }

    /// Returns the source process of each of the given windows that is cached or
    /// found, updating the cache if needed.
    ///
    /// All windows that are not cached are looked up in one scan. A window that a
    /// finished scan did not find is recorded as a miss; a scan that could not run
    /// (no permission, bounds still changing) or that ran out of time or was
    /// cancelled records none, so the next read tries again, and continues the scan.
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
        var readiness = [pid_t: Bool]()

        for window in windows {
            unsettledWindows.remove(window.windowID)
            if let pid = pids[window.windowID] {
                result[window.windowID] = pid
            } else if
                let failure = failedLookups[window.windowID],
                !SourcePIDLookupSchedule.shouldRescan(
                    failedAt: failure.failedAt,
                    now: now,
                    skippedAppIsReady: skippedAppIsReady(for: failure, at: now, readiness: &readiness)
                )
            {
                continue
            } else {
                pending.append(window)
            }
        }

        guard !pending.isEmpty else {
            return result
        }
        guard AXHelpers.isProcessTrusted() else {
            unsettledWindows.formUnion(pending.map(\.windowID))
            return result
        }
        let centers = stableCenters(of: pending)
        unsettledWindows.formUnion(pending.lazy.map(\.windowID).filter { centers[$0] == nil })
        guard !centers.isEmpty else {
            return result
        }

        let scan = scan(for: centers)
        for windowID in centers.keys {
            if case .owner(let pid) = scan.decision(for: windowID) {
                pids[windowID] = pid
                result[windowID] = pid
                failedLookups[windowID] = nil
            } else if scan.isFinished {
                // Not found, or contested: a contested window belongs to no app.
                failedLookups[windowID] = FailedLookup(failedAt: now, skippedApps: scan.skippedApps)
            } else {
                unsettledWindows.insert(windowID)
            }
        }
        return result
    }

    /// Returns whether a read of the given windows now could find a source process that
    /// the last read did not: a lookup that could not run or did not finish, a miss that a
    /// change of the running applications voided, or a miss whose skipped app no longer
    /// holds it back.
    ///
    /// A window that a finished scan did not find, and that no skipped app holds back, is
    /// not pending: a read that happens anyway looks it up again after
    /// ``SourcePIDLookupSchedule/failedLookupInterval``, but no read is made for it alone.
    /// Reading the bar again every minute for a window that no app claims would only repeat
    /// the scan.
    func hasPendingLookups(in windowIDs: [CGWindowID]) -> Bool {
        let now = ContinuousClock.now
        var readiness = [pid_t: Bool]()
        return windowIDs.contains { windowID in
            guard pids[windowID] == nil else {
                return false
            }
            if unsettledWindows.contains(windowID) {
                return true
            }
            guard let failure = failedLookups[windowID] else {
                return false
            }
            return skippedAppIsReady(for: failure, at: now, readiness: &readiness)
        }
    }

    /// Returns whether one of the apps that the given failed lookup skipped no longer holds
    /// it back: the app can be asked now, or it never finishes launching, so scans leave it
    /// out (it was still launching when it was skipped). Each app is checked once per
    /// `readiness`.
    private func skippedAppIsReady(
        for failure: FailedLookup,
        at now: ContinuousClock.Instant,
        readiness: inout [pid_t: Bool]
    ) -> Bool {
        failure.skippedApps.contains { app in
            if let ready = readiness[app.processIdentifier] {
                return ready
            }
            let ready = (app.isValidForAccessibility && schedule.mayAsk(app.processIdentifier, at: now)) || app.neverFinishesLaunching
            readiness[app.processIdentifier] = ready
            return ready
        }
    }
}
