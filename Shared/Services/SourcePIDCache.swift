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

        /// A Boolean value indicating whether the app has finished launching.
        var isFinishedLaunching: Bool {
            runningApp.isFinishedLaunching
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
        /// access on subsequent calls.
        func getOrCreateExtrasMenuBar() -> AXUIElement? {
            if let extrasMenuBar {
                return extrasMenuBar
            }
            guard
                isValidForAccessibility,
                let app = AXHelpers.application(for: runningApp),
                let bar = AXHelpers.extrasMenuBar(for: app)
            else {
                return nil
            }
            extrasMenuBar = bar
            return bar
        }
    }

    /// A scan that did not find a window's source process.
    nonisolated private struct FailedLookup {
        /// When the scan failed.
        let failedAt: ContinuousClock.Instant
        /// The apps the scan skipped because they had not finished launching. One of
        /// them may own the window once it has, which does not change the running
        /// applications.
        let launchingApps: [CachedApplication]
    }

    /// The shared cache.
    nonisolated static let shared = SourcePIDCache()

    /// How long a window whose source process was not found is not scanned again.
    static let failedLookupInterval = Duration.seconds(30)

    /// The queue that runs the cache, and with it every blocking Accessibility call
    /// of a scan.
    private let queue: DispatchSerialQueue

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private let logger = Logger(category: "SourcePIDCache")

    private var apps = [CachedApplication]()

    private var pids = [CGWindowID: pid_t]()

    /// Windows whose source process was not found by a scan. A miss is not scanned
    /// again for ``failedLookupInterval``, or until an app the scan skipped has
    /// finished launching: every scan asks every running app through Accessibility
    /// (jordanbaird/Ice#911). Starts empty whenever the running applications change,
    /// as a new app may own the window.
    private var failedLookups = [CGWindowID: FailedLookup]()

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
    }

    /// Returns the latest bounds of the given window after ensuring
    /// that the bounds are stable (a.k.a. not currently changing).
    ///
    /// This method blocks until stable bounds can be determined, or
    /// until retrieving the bounds for the window fails.
    private func stableBounds(for window: WindowInfo) -> CGRect? {
        var cachedBounds = window.bounds

        for n in 1...5 {
            guard let currentBounds = window.currentBounds() else {
                // Failure here means the window probably doesn't
                // exist anymore.
                return nil
            }
            if currentBounds == cachedBounds {
                return currentBounds
            }
            cachedBounds = currentBounds
            // Compute the sleep interval from the current attempt.
            Thread.sleep(forTimeInterval: TimeInterval(n) / 100)
        }

        return nil
    }

    /// Reorders the cached apps so that those that are confirmed
    /// to have an extras menu bar are first in the array.
    private func partitionApps() {
        apps = apps.filter(\.hasExtrasMenuBar) + apps.filter { !$0.hasExtrasMenuBar }
    }

    /// Updates the cached process identifier for the given window.
    ///
    /// - Returns: The apps the scan skipped because they had not finished
    ///   launching, or `nil` if no scan ran.
    private func updatePID(for window: WindowInfo) -> [CachedApplication]? {
        guard
            AXHelpers.isProcessTrusted(),
            let windowBounds = stableBounds(for: window)
        else {
            return nil
        }

        partitionApps()

        var launchingApps = [CachedApplication]()

        for app in apps {
            guard let bar = app.getOrCreateExtrasMenuBar() else {
                if !app.isFinishedLaunching {
                    launchingApps.append(app)
                }
                continue
            }
            for child in AXHelpers.children(for: bar) {
                guard AXHelpers.isEnabled(child) else {
                    continue
                }
                guard
                    let childFrame = AXHelpers.frame(for: child),
                    childFrame.center.distance(to: windowBounds.center) <= 1
                else {
                    continue
                }
                pids[window.windowID] = app.processIdentifier
                return launchingApps
            }
        }

        return launchingApps
    }

    /// Returns the cached process identifier for the given window,
    /// updating the cache if needed.
    ///
    /// Starts the cache if nothing has yet, so an item read before the backend's
    /// setup still works.
    func pid(for window: WindowInfo) -> pid_t? {
        if observation == nil {
            start()
        }
        dispatchPrecondition(condition: .onQueue(queue))
        if let pid = pids[window.windowID] {
            return pid
        }
        let now = ContinuousClock.now
        if
            let failure = failedLookups[window.windowID],
            failure.failedAt.duration(to: now) < Self.failedLookupInterval,
            !failure.launchingApps.contains(where: \.isFinishedLaunching)
        {
            return nil
        }
        // Only a scan that ran records a miss; one that could not run (no
        // permission, bounds still changing) is retried on the next lookup.
        guard let launchingApps = updatePID(for: window) else {
            return nil
        }
        guard let pid = pids[window.windowID] else {
            failedLookups[window.windowID] = FailedLookup(failedAt: now, launchingApps: launchingApps)
            return nil
        }
        failedLookups[window.windowID] = nil
        return pid
    }
}
