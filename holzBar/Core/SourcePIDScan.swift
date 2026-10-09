//
//  SourcePIDScan.swift
//  holzBar
//

import CoreGraphics

/// What a scan asks the running apps, and the clock it measures them with.
///
/// The cache answers through Accessibility, the tests from a script.
nonisolated protocol SourcePIDScanSource {
    /// A running app.
    associatedtype App
    /// An element of an app's extras menu bar.
    associatedtype Element

    /// The current time. Every call below may take a while.
    var now: ContinuousClock.Instant { get }

    /// Whether the task the scan runs in was cancelled.
    var isCancelled: Bool { get }

    /// The app's process.
    func pid(of app: App) -> pid_t

    /// Whether the app's code is signed by Apple.
    func isSignedByApple(_ app: App) -> Bool

    /// Whether the app is in a state in which it can be asked: finished launching and
    /// responsive.
    func isValidForAccessibility(_ app: App) -> Bool

    /// Whether the app never finishes launching
    /// (``SourcePIDLookupSchedule/neverFinishesLaunching(isFinishedLaunching:runningFor:)``),
    /// so it can neither be asked nor waited for.
    func neverFinishesLaunching(_ app: App) -> Bool

    /// The app's extras menu bar, or `nil` if it has none.
    func extrasMenuBar(of app: App) -> Element?

    /// The items of an extras menu bar.
    func children(of element: Element) -> [Element]

    /// The frame an app reports for one of its items.
    func frame(of element: Element) -> CGRect?

    /// Whether an item is enabled.
    func isEnabled(_ element: Element) -> Bool
}

/// One scan over the running apps for the items at some window centres on macOS 26, which
/// a later read can continue.
///
/// A scan asks the apps in the order given, stops at ``SourcePIDLookupSchedule/lookupBudget``,
/// and pauses an app that ran into the messaging timeout or used up
/// ``SourcePIDLookupSchedule/appBudget``. A scan that stopped early keeps what it learned,
/// and the next read continues it with the apps it has not asked yet
/// (``continued(for:at:)``), so a few slow apps delay a finished scan by a read or two
/// instead of keeping every app that is not signed by Apple from ever getting its items.
///
/// The type knows nothing about Accessibility, so it can be tested on its own.
nonisolated struct SourcePIDScan<App> {
    /// The windows the scan looks for, with their centres.
    private(set) var centers: [CGWindowID: CGPoint]

    /// When the first part of the scan started.
    let startedAt: ContinuousClock.Instant

    /// The apps that report an item at each window's centre.
    private(set) var claims = [CGWindowID: SourcePIDClaims]()

    /// Whether every app was asked or skipped, rather than the scan running out of time or
    /// being cancelled.
    private(set) var isFinished = false

    /// The apps the scan could not ask, because they were launching, unresponsive or
    /// paused, or ran into the timeout. holzBar's own process is never one of them, and
    /// neither is an app that never finishes launching: it is not waited for.
    private(set) var skippedApps = [App]()

    /// Whether an app signed by Apple was skipped. Its item could be at a centre that
    /// another app claims, so no other app gets a window until it was asked.
    private(set) var skippedAppleApp = false

    /// The apps that were asked or skipped.
    private var doneApps = Set<pid_t>()

    /// Creates a scan for the given window centres.
    init(centers: [CGWindowID: CGPoint], startedAt: ContinuousClock.Instant) {
        self.centers = centers
        self.startedAt = startedAt
    }

    /// Which app the window with the given identifier belongs to.
    func decision(for windowID: CGWindowID) -> SourcePIDClaims.Decision {
        claims[windowID, default: SourcePIDClaims()].decision(
            scanFinished: isFinished,
            appleAppsComplete: !skippedAppleApp
        )
    }

    /// The part of this scan that the next read continues, for the windows that are still
    /// looked up then, or `nil` if it starts over.
    ///
    /// A scan starts over once it finished, after ``SourcePIDLookupSchedule/scanLifetime``,
    /// and when a window is new or moved: the apps already asked were not asked about it.
    func continued(for centers: [CGWindowID: CGPoint], at now: ContinuousClock.Instant) -> Self? {
        guard
            !isFinished,
            startedAt.duration(to: now) < SourcePIDLookupSchedule.scanLifetime,
            centers.allSatisfy({ self.centers[$0.key] == $0.value })
        else {
            return nil
        }
        var scan = self
        scan.centers = centers
        scan.claims = claims.filter { centers.keys.contains($0.key) }
        return scan
    }

    /// Asks the given apps, except those this scan asked or skipped before, which of their
    /// items sit at the window centres, until every window is settled, every app was asked,
    /// the budget is used up or the task is cancelled.
    ///
    /// - Returns: The apps that this part of the scan paused.
    @discardableResult
    mutating func run<Source: SourcePIDScanSource>(
        over apps: [App],
        with source: Source,
        schedule: inout SourcePIDLookupSchedule
    ) -> [pid_t] where Source.App == App {
        let start = source.now
        var paused = [pid_t]()
        var remaining = centers.filter { claims[$0.key]?.isSettled != true }

        func stops() -> Bool {
            source.isCancelled || SourcePIDLookupSchedule.isOverBudget(startedAt: start, now: source.now)
        }

        func skip(_ app: App, isSignedByApple: Bool) {
            skippedApps.append(app)
            skippedAppleApp = skippedAppleApp || isSignedByApple
        }

        /// Measures a call: whether it ran into the messaging timeout.
        func timed<Value>(_ call: () -> Value) -> (value: Value, timedOut: Bool) {
            let callStart = source.now
            let value = call()
            return (value, SourcePIDLookupSchedule.didTimeOut(after: callStart.duration(to: source.now)))
        }

        for app in apps where !remaining.isEmpty {
            if stops() {
                return paused
            }
            let pid = source.pid(of: app)
            guard !doneApps.contains(pid) else {
                continue
            }
            // Neither asked nor skipped: waiting for an app that never finishes launching,
            // such as WebKit's XPC services, would keep every other app from its windows
            // as long as it runs.
            guard !source.neverFinishesLaunching(app) else {
                doneApps.insert(pid)
                continue
            }
            let isSignedByApple = source.isSignedByApple(app)
            let appStart = source.now
            guard schedule.mayAsk(pid, at: appStart), source.isValidForAccessibility(app) else {
                doneApps.insert(pid)
                skip(app, isSignedByApple: isSignedByApple)
                continue
            }

            var timedOut = false
            let bar = timed { source.extrasMenuBar(of: app) }
            if bar.timedOut {
                timedOut = true
            } else if let extrasMenuBar = bar.value {
                let children = timed { source.children(of: extrasMenuBar) }
                timedOut = children.timedOut
                for child in children.value.prefix(SourcePIDLookupSchedule.maximumChildren) where !timedOut {
                    // The app's budget first: the first app a part of the scan asks is
                    // always done with when the part ends, so every part gets further.
                    if SourcePIDLookupSchedule.isOverAppBudget(startedAt: appStart, now: source.now) {
                        timedOut = true
                        break
                    }
                    if stops() {
                        // Not done: the next part of the scan asks this app again.
                        return paused
                    }
                    // The frame first: `isEnabled` is only read for an item at a window's
                    // centre, which gives the same result with about half the calls.
                    let frame = timed { source.frame(of: child) }
                    if frame.timedOut {
                        timedOut = true
                        break
                    }
                    guard let childFrame = frame.value else {
                        continue
                    }
                    let matches = remaining.filter { hypot(childFrame.midX - $0.value.x, childFrame.midY - $0.value.y) <= 1 }.keys
                    guard !matches.isEmpty else {
                        continue
                    }
                    let enabled = timed { source.isEnabled(child) }
                    if enabled.timedOut {
                        timedOut = true
                        break
                    }
                    guard enabled.value else {
                        continue
                    }
                    let claim = SourcePIDClaims.Claim(pid: pid, isSignedByApple: isSignedByApple)
                    for windowID in matches {
                        claims[windowID, default: SourcePIDClaims()].add(claim)
                        if claims[windowID]?.isSettled == true {
                            remaining[windowID] = nil
                        }
                    }
                }
            }

            doneApps.insert(pid)
            schedule.record(pid, timedOut: timedOut, at: source.now)
            if timedOut, schedule.mayPause(pid) {
                // holzBar's own process is never paused, and is not waited for either.
                paused.append(pid)
                skip(app, isSignedByApple: isSignedByApple)
            }
        }
        isFinished = true
        return paused
    }
}
