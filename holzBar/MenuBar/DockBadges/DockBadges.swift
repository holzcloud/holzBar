//
//  DockBadges.swift
//  holzBar
//

import Foundation
import Observation

/// The Dock badges module: the apps in the Dock the user can choose from, so that their Dock
/// badge can show in the menu bar.
///
/// The module is off until the user switches it on and costs nothing while off: it holds no
/// list, no task and no observer. Even with the module on, it reads the Dock only while the
/// module's settings are open (``settingsDidAppear()``), through ``DockReader`` off the main
/// actor, and drops what it read when they close (``settingsDidDisappear()``) or the module goes
/// off. App names and bundle identifiers stay in memory and are never logged.
@MainActor
@Observable
final class DockBadges {
    /// The identifier of the module in ``ModuleCatalog``.
    static let moduleID = "dock-badges"

    /// What the last read of the Dock said.
    enum ListState: Equatable {
        /// Nothing has been read yet, or the list was dropped.
        case notRead
        /// The Dock was read; ``dockApps`` is what it lists.
        case read
        /// The Dock could not be read; ``dockApps`` keeps what an earlier read found.
        case unreadable
    }

    /// The applications the Dock listed at the last read, in the Dock's order. Empty while the
    /// module is off or its settings are closed.
    private(set) var dockApps = [DockAppItem]()

    /// What the last read of the Dock said.
    private(set) var listState = ListState.notRead

    @ObservationIgnored private weak var appState: AppState?

    /// Follows the module switch; the only observation that exists while the module is off.
    @ObservationIgnored private var moduleLoop: ObservationLoop?

    /// Whether the module's settings are open.
    @ObservationIgnored private var isSettingsOpen = false

    /// The read that is running, if any.
    @ObservationIgnored private var readTask: Task<Void, Never>?

    /// The names of chosen apps that are not in the Dock, found once per opening.
    @ObservationIgnored private var namesOfAppsOutsideTheDock = [String: String]()

    // MARK: Setup

    /// Follows the module switch. With the module off, nothing else is created.
    func performSetup(with appState: AppState) {
        self.appState = appState
        moduleLoop = ObservationLoop.observe { [weak appState] in
            appState?.modules.isEnabled(Self.moduleID) ?? false
        } onChange: { [weak self] _ in
            self?.update()
        }
    }

    // MARK: Settings

    /// The module's settings opened: reads the Dock once, when the module is on and holzBar has
    /// Accessibility.
    func settingsDidAppear() {
        isSettingsOpen = true
        update()
    }

    /// The module's settings closed: cancels a running read and drops the list.
    func settingsDidDisappear() {
        isSettingsOpen = false
        update()
    }

    /// The rows of the settings for the chosen apps and the Dock as it was read.
    func rows(chosen: [String]) -> [DockAppRow] {
        DockBadgeApps.rows(chosen: chosen, dock: dockApps) { [self] bundleID in
            if let known = namesOfAppsOutsideTheDock[bundleID] {
                return known
            }
            guard let name = BuiltInItemActions.applicationName(forBundleID: bundleID) else {
                return nil
            }
            namesOfAppsOutsideTheDock[bundleID] = name
            return name
        }
    }

    // MARK: Reading

    private var isModuleOn: Bool {
        appState?.modules.isEnabled(Self.moduleID) ?? false
    }

    /// Brings the reading in line with the module switch and the open settings.
    private func update() {
        guard isSettingsOpen, isModuleOn else {
            stopReading()
            return
        }
        if appState?.permissions.accessibility.hasPermission == true {
            read()
        }
    }

    private func read() {
        readTask?.cancel()
        readTask = Task { [weak self] in
            let result = await DockReader.applicationItems()
            guard !Task.isCancelled else {
                return
            }
            self?.finishRead(result)
        }
    }

    private func finishRead(_ result: DockReader.Result) {
        guard isSettingsOpen, isModuleOn else {
            return
        }
        switch result {
        case .items(let items):
            dockApps = items
            listState = .read
        case .dockMissing, .failed:
            listState = .unreadable
        }
    }

    /// Cancels a running read and drops everything that was read.
    private func stopReading() {
        readTask?.cancel()
        readTask = nil
        if !dockApps.isEmpty {
            dockApps = []
        }
        if listState != .notRead {
            listState = .notRead
        }
        namesOfAppsOutsideTheDock.removeAll()
    }
}
