//
//  NotShownList27.swift
//  holzBar
//

import AppKit
import ApplicationServices
import Observation
import os

/// The list of apps macOS 27 does not show in the menu bar (Phase 97, D-13, D-18), for the
/// group Not shown by macOS in Layout.
///
/// The list exists only while Layout is open: ``layoutDidOpen()`` starts one observation of
/// ``Concealer27/unnameableVisible`` and ``layoutDidClose()`` stops it and drops the rows, so
/// with Layout closed nothing runs and nothing is kept. The names and paths come from the
/// running applications, stay in memory only and are never logged.
///
/// Two kinds of app are listed. Those with a bundle identifier come from the concealer's
/// ``Concealer27/unnameableVisible``. Processes without one are found by one bounded
/// Accessibility scan per opening of Layout: holzBar's own reads of the bar skip them, so the
/// scan asks each for its extras menu bar once, on its own queue, with a short timeout.
@available(macOS 27.0, *)
@MainActor
@Observable
final class NotShownList27 {
    /// The rows the group shows, in the order of ``NotShownApps/rows(_:)``.
    private(set) var rows = [NotShownApps.Row]()

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var loop: ObservationLoop?

    /// The sources of the apps that have a bundle identifier, from the last value observed.
    @ObservationIgnored private var identified = [NotShownApps.Source]()

    /// The sources of the processes without a bundle identifier that own menu bar items, from the
    /// scan of this opening.
    @ObservationIgnored private var bundleless = [NotShownApps.Source]()

    /// The one scan of this opening; cancelled when Layout closes.
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    /// A running process without a bundle identifier.
    typealias Candidate = (pid: pid_t, name: String?, path: String?)

    /// How long one process may take to answer the scan.
    nonisolated private static let messagingTimeout: Float = 0.25

    /// The scan blocks on other processes, so it runs on its own queue, off the Swift
    /// concurrency pool.
    nonisolated private static let scanQueue = DispatchQueue(label: "com.holzcloud.holzBar.NotShownList27", qos: .utility)

    init(appState: AppState?) {
        self.appState = appState
    }

    /// Starts following the apps macOS cannot name. Layout calls it when it appears; a second
    /// call while the list is open changes nothing.
    func layoutDidOpen() {
        guard loop == nil, let appState else {
            return
        }
        let concealer = appState.concealer27
        loop = ObservationLoop.observe({ concealer.unnameableVisible }, onChange: { [weak self] bundleIDs in
            self?.update(bundleIDs: bundleIDs)
        })
        update(bundleIDs: concealer.unnameableVisible)
        startScan()
    }

    /// Stops following and drops the rows. Layout calls it when it disappears.
    func layoutDidClose() {
        loop?.cancel()
        loop = nil
        scanTask?.cancel()
        scanTask = nil
        identified = []
        bundleless = []
        if !rows.isEmpty {
            rows = []
        }
    }

    /// Builds one source per bundle identifier from the running application: its name, its
    /// bundle and the reason by the install-location rule (an app only confirmed by the overlap
    /// heuristic is not named by the rule).
    private func update(bundleIDs: [String]) {
        identified = bundleIDs.map { bundleID in
            let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            let bundleURL = application?.bundleURL
            let byRule = UnnameableApps27.isUnnameable(
                bundleID: bundleID,
                bundlePath: UnnameableApps27.rulePath(of: bundleURL)
            )
            let fallback = bundleURL?.deletingPathExtension().lastPathComponent ?? ""
            return NotShownApps.Source(
                id: bundleID,
                name: application?.localizedName,
                fallbackName: fallback.isEmpty ? bundleID : fallback,
                path: bundleURL?.path,
                reason: NotShownApps.reason(unnameableByRule: byRule)
            )
        }
        publish()
    }

    /// Starts the scan of the processes without a bundle identifier: once per opening, in one task.
    private func startScan() {
        let candidates = NSWorkspace.shared.runningApplications.compactMap { application -> Candidate? in
            guard application.bundleIdentifier == nil, !application.isTerminated else {
                return nil
            }
            return (application.processIdentifier, application.localizedName, application.executableURL?.path ?? application.bundleURL?.path)
        }
        guard !candidates.isEmpty else {
            return
        }
        scanTask = Task { [weak self] in
            let owners = await Self.bundlelessOwners(candidates)
            guard !Task.isCancelled, let self else {
                return
            }
            bundleless = owners.map { owner in
                let last = owner.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
                return NotShownApps.Source(
                    id: "pid:\(owner.pid)",
                    name: owner.name,
                    fallbackName: last.isEmpty ? String(localized: "Process \(Int(owner.pid))") : last,
                    path: owner.path,
                    reason: .noAppIdentifier
                )
            }
            publish()
        }
    }

    /// The candidates that own at least one menu bar item. Each is asked once for its extras menu
    /// bar with a 0.25 s messaging timeout, one after the other on the scan queue; a hung
    /// process costs at most that timeout, and a cancelled task stops before the next one.
    nonisolated static func bundlelessOwners(_ candidates: [Candidate]) async -> [Candidate] {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                scanQueue.async {
                    var owners = [Candidate]()
                    for candidate in candidates {
                        if cancelled.withLock({ $0 }) {
                            break
                        }
                        if ownsMenuBarItems(pid: candidate.pid) {
                            owners.append(candidate)
                        }
                    }
                    continuation.resume(returning: owners)
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    /// Whether the process answers with an extras menu bar that has at least one child.
    nonisolated private static func ownsMenuBarItems(pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var barValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXExtrasMenuBarAttribute as CFString, &barValue) == .success,
            let barValue,
            CFGetTypeID(barValue) == AXUIElementGetTypeID()
        else {
            return false
        }
        let bar = barValue as! AXUIElement // swiftlint:disable:this force_cast
        var childrenValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
            let children = childrenValue as? [AXUIElement]
        else {
            return false
        }
        return !children.isEmpty
    }

    /// Rebuilds the rows from every kind of source.
    private func publish() {
        let built = NotShownApps.rows(identified + bundleless)
        if built != rows {
            rows = built
        }
    }
}
