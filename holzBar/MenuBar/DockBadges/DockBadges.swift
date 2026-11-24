//
//  DockBadges.swift
//  holzBar
//

import AppKit
import Foundation
import Observation

/// The Dock badges module: the apps in the Dock the user can choose from, so that their Dock
/// badge can show in the menu bar.
///
/// The module is off until the user switches it on and costs nothing while off: it holds no
/// list, no task and no observer. Even with the module on, it reads the Dock only while the
/// module's settings are open (``settingsDidAppear()``), through ``DockReader`` off the main
/// actor, and drops what it read when they close (``settingsDidDisappear()``) or the module goes
/// off. While they are open it reads again when an app launches or quits (the Dock then adds or
/// removes an icon) after one short wait, and when Accessibility is granted or withdrawn; there is
/// no timer. App names and bundle identifiers stay in memory and are never logged.
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

    /// The observations of launching and quitting apps, and the wait that follows one. They exist
    /// only while the settings are open and the module is on.
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var terminateTask: Task<Void, Never>?
    @ObservationIgnored private var rereadTask: Task<Void, Never>?

    /// Follows Accessibility while the settings are open and the module is on.
    @ObservationIgnored private var permissionLoop: ObservationLoop?

    /// How long to wait after an app launched or quit before the Dock is read again, so that the
    /// Dock has added or removed its icon.
    private static let dockSettleWait = Duration.milliseconds(500)

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

    /// Whether holzBar has the Accessibility permission now.
    private var hasAccessibility: Bool {
        appState?.permissions.accessibility.hasPermission ?? false
    }

    /// Brings the reading in line with the module switch, the open settings and the permission.
    private func update() {
        guard isSettingsOpen, isModuleOn else {
            stopReading()
            return
        }
        startObserving()
        if hasAccessibility {
            read()
        } else {
            dropList()
        }
    }

    /// Starts following launching and quitting apps and the permission; does nothing when it
    /// already does.
    private func startObserving() {
        guard launchTask == nil else {
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        launchTask = Task { [weak self] in
            for await _ in center.notifications(named: NSWorkspace.didLaunchApplicationNotification) {
                self?.appsDidChange()
            }
        }
        terminateTask = Task { [weak self] in
            for await _ in center.notifications(named: NSWorkspace.didTerminateApplicationNotification) {
                self?.appsDidChange()
            }
        }
        permissionLoop = ObservationLoop.observe { [weak appState] in
            appState?.permissions.accessibility.hasPermission ?? false
        } onChange: { [weak self] _ in
            self?.update()
        }
    }

    /// An app launched or quit: the Dock changes its icons a moment later, so wait once (a new
    /// event replaces the wait) and read again.
    private func appsDidChange() {
        guard isSettingsOpen, isModuleOn, hasAccessibility else {
            return
        }
        rereadTask?.cancel()
        rereadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dockSettleWait, tolerance: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            self?.read()
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
        guard isSettingsOpen, isModuleOn, hasAccessibility else {
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

    /// Cancels every task and observation and drops everything that was read.
    private func stopReading() {
        launchTask?.cancel()
        launchTask = nil
        terminateTask?.cancel()
        terminateTask = nil
        rereadTask?.cancel()
        rereadTask = nil
        permissionLoop?.cancel()
        permissionLoop = nil
        dropList()
        namesOfAppsOutsideTheDock.removeAll()
    }

    /// Cancels a running read and forgets the list.
    private func dropList() {
        readTask?.cancel()
        readTask = nil
        if !dockApps.isEmpty {
            dockApps = []
        }
        if listState != .notRead {
            listState = .notRead
        }
    }
}
