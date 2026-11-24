//
//  DockBadges.swift
//  holzBar
//

import AppKit
import Foundation
import Observation

/// The Dock badges module: the apps in the Dock the user can choose from, and the badge of the
/// chosen ones as menu bar items.
///
/// The module is off until the user switches it on and costs nothing while off: it holds no
/// list, no item, no task and no observer but the one that follows the module switch. Even with
/// the module on, it reads the Dock's list only while the
/// module's settings are open (``settingsDidAppear()``), through ``DockReader`` off the main
/// actor, and drops what it read when they close (``settingsDidDisappear()``) or the module goes
/// off. While they are open it reads again when an app launches or quits (the Dock then adds or
/// removes an icon) after one short wait, and when Accessibility is granted or withdrawn; there is
/// no timer for the list.
///
/// The badges are a separate part, active only while the module is on, the Read badge counts
/// switch is on and holzBar has Accessibility (``DockBadgeItems`` shows one item per chosen app
/// outside a group and one per group, ``DockBadgeItemList``; nothing exists otherwise). Then one task reads a pass over the Dock at once and every 30
/// seconds while at least one app is chosen and the Mac is not asleep, locked or away. The read
/// goes through a private macOS interface, so it has a start check and a self-switch-off
/// (``PrivateFeatureGate`` and ``DockLabelGate``): when the Dock does not offer the badge, or
/// three passes in a row fail, the items go and ``countsAreUnavailable`` says so until the user
/// switches Read badge counts off and on. A change of that switch, of the module, of Accessibility
/// or of the chosen apps bumps a generation, and a pass that finishes under an older one neither
/// calls the bridge again nor counts. App names, bundle identifiers and badge texts stay in
/// memory and are never logged.
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

    /// Whether the Read badge counts switch is on and the badge read switched itself off for this
    /// session: the Dock does not offer the badge, or three passes in a row failed. The items are
    /// gone and nothing is read until the switch is turned off and on.
    private(set) var countsAreUnavailable = false

    /// How long the task of the badges waits between two passes.
    private static let passInterval = Duration.seconds(30)

    /// What decides whether the badges are active and what they show.
    private struct BadgeInputs: Equatable {
        /// Module on, Read badge counts on and Accessibility granted.
        var isActive = false
        /// The chosen apps, in the order chosen.
        var apps = [String]()
        /// The groups of the chosen apps.
        var groups = [DockBadgeGroup]()
        /// Whether the Mac is asleep, locked or away.
        var isPaused = false
        /// What an item shows while its count is zero.
        var zeroMode = DockBadgeZeroMode.dim
    }

    /// Follows the badge inputs. While the module is off it reads only the module switch, so that
    /// is all it observes.
    @ObservationIgnored private var badgeLoop: ObservationLoop?

    /// The menu bar items; exists only while the badges are active and the read is available.
    @ObservationIgnored private var items: DockBadgeItems?

    /// The task that reads a pass now and then, and the apps it was started for.
    @ObservationIgnored private var passTask: Task<Void, Never>?
    @ObservationIgnored private var passApps = [String]()

    /// The start check, until it decides, and the gate it then makes. `nil` until a pass decided.
    @ObservationIgnored private var startCheck = DockLabelGate.StartCheck()
    @ObservationIgnored private var gate: PrivateFeatureGate?

    /// Changes whenever a pass that is running must be dropped.
    @ObservationIgnored private var passGeneration = 0

    /// The badge of each chosen app at the last pass.
    @ObservationIgnored private var labels = [String: DockBadgeLabel]()

    /// The pictures holzBar draws of the items, by autosave name, for the Shelf, the Layout pane
    /// and the search. In memory only; empty while there are no items.
    private var pictures = [String: NSImage]()

    /// Follows where the items stand (their sections and whether the Mac is in use); exists only
    /// while the items do.
    @ObservationIgnored private var visibilityLoop: ObservationLoop?

    // MARK: Setup

    /// Follows the module switch. With the module off, nothing else is created.
    func performSetup(with appState: AppState) {
        self.appState = appState
        moduleLoop = ObservationLoop.observe { [weak appState] in
            appState?.modules.isEnabled(Self.moduleID) ?? false
        } onChange: { [weak self] _ in
            self?.update()
        }
        badgeLoop = ObservationLoop.observe { [weak self] in
            self?.badgeInputs() ?? BadgeInputs()
        } onChange: { [weak self] _ in
            self?.refreshBadges()
        }
        refreshBadges()
    }

    /// The picture holzBar draws of the item with the given autosave name, or `nil` when it is not
    /// in the menu bar.
    func image(forAutosaveName name: String) -> NSImage? {
        pictures[name]
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

    // MARK: Badges

    private func badgeInputs() -> BadgeInputs {
        guard isModuleOn, let appState, appState.settings.dockBadges.readsCounts, hasAccessibility else {
            return BadgeInputs()
        }
        return BadgeInputs(
            isActive: true,
            apps: appState.settings.dockBadges.apps,
            groups: appState.settings.dockBadges.groups,
            isPaused: appState.systemActivityMonitor.isPaused,
            zeroMode: appState.settings.dockBadges.zeroMode
        )
    }

    /// The Read badge counts switch changed. The start check and the failure count begin afresh,
    /// so a read that switched itself off tries again when the user turns the switch on.
    func readsCountsDidChange() {
        cancelPasses()
        gate = nil
        startCheck = DockLabelGate.StartCheck()
        labels.removeAll()
        if countsAreUnavailable {
            countsAreUnavailable = false
        }
        refreshBadges()
    }

    /// Brings the items and the task in line with the inputs: nothing while the badges are not
    /// active or the read switched itself off, the items while they are, and the task while an
    /// app is chosen and the Mac is in use.
    private func refreshBadges() {
        let inputs = badgeInputs()
        guard inputs.isActive else {
            stopBadges()
            return
        }
        guard !hasSwitchedItselfOff else {
            stopBadges()
            updateAvailability()
            return
        }
        let apps = inputs.apps
        let appItems = items ?? makeItems()
        items = appItems
        labels = labels.filter { apps.contains($0.key) }
        let kinds = DockBadgeItemList.items(apps: apps, groups: inputs.groups)
        appItems.update(kinds: kinds, apps: apps, groups: inputs.groups, labels: labels, zeroMode: inputs.zeroMode)
        appItems.apply(visibility: visibilityInputs())
        guard !apps.isEmpty, !inputs.isPaused else {
            cancelPasses()
            return
        }
        if passTask == nil || passApps != apps {
            startPasses(for: apps)
        }
    }

    /// Creates the items and starts following where they stand.
    private func makeItems() -> DockBadgeItems {
        visibilityLoop = ObservationLoop.observe { [weak self] in
            self?.visibilityInputs() ?? DockBadgeVisibility.Inputs()
        } onChange: { [weak self] inputs in
            self?.items?.apply(visibility: inputs)
        }
        return DockBadgeItems { [weak self] name, picture in
            guard let self else {
                return
            }
            if let picture {
                pictures[name] = picture
            } else if pictures[name] != nil {
                pictures[name] = nil
            }
        }
    }

    /// Where the chosen apps' items stand now.
    private func visibilityInputs() -> DockBadgeVisibility.Inputs {
        guard let appState else {
            return DockBadgeVisibility.Inputs()
        }
        let settings = appState.settings.dockBadges
        let names = DockBadgeItemList.items(apps: settings.apps, groups: settings.groups).map(\.autosaveName)
        return DockBadgeVisibility.inputs(for: names, in: appState)
    }

    /// Takes the items out, keeping their places, and cancels the task.
    private func stopBadges() {
        cancelPasses()
        visibilityLoop?.cancel()
        visibilityLoop = nil
        items?.removeAll(keepingPosition: true)
        items = nil
        labels.removeAll()
    }

    private func cancelPasses() {
        passGeneration &+= 1
        passTask?.cancel()
        passTask = nil
        passApps = []
    }

    private func startPasses(for apps: [String]) {
        cancelPasses()
        passApps = apps
        let generation = passGeneration
        passTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runPass(generation: generation)
                guard !Task.isCancelled else {
                    return
                }
                try? await Task.sleep(for: Self.passInterval, tolerance: .seconds(5))
            }
        }
    }

    /// Reads one pass over the Dock and acts on it: the start check until it decides, then the
    /// gate's success or failure, and the items' badges while the read is available.
    private func runPass(generation: Int) async {
        guard generation == passGeneration, let settings = appState?.settings.dockBadges else {
            return
        }
        let result = await DockReader.labels(of: Set(settings.apps), readsLabels: gate?.isAvailable ?? true)
        // A pass that finishes after something changed neither counts nor shows.
        guard !Task.isCancelled, generation == passGeneration else {
            return
        }
        if gate == nil {
            guard let load = startCheck.record(result.pass) else {
                return
            }
            gate = PrivateFeatureGate(isEnabled: true, load: load)
        }
        if gate?.isAvailable == true {
            switch DockLabelGate.outcome(result.pass) {
            case .success: gate?.recordSuccess()
            case .failure: gate?.recordFailure()
            case .nothingRead: break
            }
        }
        updateAvailability()
        guard !hasSwitchedItselfOff else {
            refreshBadges()
            return
        }
        if result.pass.dockReadable {
            labels = result.answers.mapValues { DockBadgeLabel($0) }
            let kinds = DockBadgeItemList.items(apps: settings.apps, groups: settings.groups)
            items?.update(
                kinds: kinds,
                apps: settings.apps,
                groups: settings.groups,
                labels: labels,
                zeroMode: settings.zeroMode
            )
        }
    }

    /// Whether the gate exists and is unavailable for a reason other than the switch being off.
    private var hasSwitchedItselfOff: Bool {
        guard let gate, case .unavailable(let reason) = gate.state else {
            return false
        }
        return reason != .switchedOff
    }

    private func updateAvailability() {
        if countsAreUnavailable != hasSwitchedItselfOff {
            countsAreUnavailable = hasSwitchedItselfOff
        }
    }
}
