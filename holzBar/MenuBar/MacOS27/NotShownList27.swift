//
//  NotShownList27.swift
//  holzBar
//

import AppKit
import Observation

/// The list of apps macOS 27 does not show in the menu bar (Phase 97, D-13, D-18), for the
/// group Not shown by macOS in Layout.
///
/// The list exists only while Layout is open: ``layoutDidOpen()`` starts one observation of
/// ``Concealer27/unnameableVisible`` and ``layoutDidClose()`` stops it and drops the rows, so
/// with Layout closed nothing runs and nothing is kept. The names and paths come from the
/// running applications, stay in memory only and are never logged.
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
    }

    /// Stops following and drops the rows. Layout calls it when it disappears.
    func layoutDidClose() {
        loop?.cancel()
        loop = nil
        identified = []
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

    /// Rebuilds the rows from every kind of source.
    private func publish() {
        let built = NotShownApps.rows(identified)
        if built != rows {
            rows = built
        }
    }
}
