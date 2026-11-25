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
/// outside a group and one per group, ``DockBadgeItemList``; nothing exists otherwise).
///
/// The Dock is read only while at least one badge or group item is in a section the bar shows and
/// the Mac is in use, with the settle time after a wake (``ReadoutVisibility``, the rule of the
/// system readouts); an item that is only hidden by the zero mode Hide counts as shown, so its
/// badge can come back. Then one ``DockObserver`` follows the Dock's notifications and
/// ``DockBadgeRefresh`` decides when a pass reads the chosen apps' badges: after a notification,
/// a second after one of the chosen apps was activated, launched or quit, and by a timer with
/// back-off only until a notified read has found a change (``refreshPolls`` says the Dock stays
/// silent, so the timer stays). While no item can be seen there is no observer, no wait and no
/// read. A Dock that restarts is found again.
///
/// The read goes through a private macOS interface, so it has a start check and a
/// self-switch-off (``PrivateFeatureGate`` and ``DockLabelGate``): when the Dock does not offer the
/// badge, or three passes in a row fail, the items go and ``countsAreUnavailable`` says so until
/// the user switches Read badge counts off and on. Three passes in a row that could not read the
/// Dock's tree at all set ``readerFailed``, which the settings say; the items keep their last
/// values. A change of that switch, of the module, of Accessibility or of the chosen apps bumps a
/// generation, and a pass that finishes under an older one neither calls the bridge again nor
/// counts. App names, bundle identifiers and badge texts stay in memory and are never logged.
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

    /// Whether the Dock stays silent about badge changes, so the badges refresh on a timer (every 30
    /// seconds at first, backing off while nothing changes). Settings says so.
    private(set) var refreshPolls = false

    /// Whether the last three passes in a row could not read the Dock's list at all. The items keep
    /// their last values; the next pass that works clears it.
    private(set) var readerFailed = false

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

    /// The pass that is running, and the apps the reader was registered for.
    @ObservationIgnored private var passTask: Task<Void, Never>?
    @ObservationIgnored private var passApps = [String]()

    /// When the reader reads again, and whether it exists at all: the rule, its visibility, the one
    /// wait it names, the wait for the settle time, the observer of the Dock and the observations of
    /// the chosen apps. All of them exist only while the reader is registered.
    @ObservationIgnored private var refresh = DockBadgeRefresh()
    @ObservationIgnored private var readVisibility = ReadoutVisibility()
    @ObservationIgnored private var waitTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var dockObserver: DockObserver?
    @ObservationIgnored private var workspaceTasks = [Task<Void, Never>]()

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
            // A read of the Dock's tree that works clears the failure the reader reported.
            refresh.readWorked()
            syncRefreshState()
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
        stopReader()
        gate = nil
        startCheck = DockLabelGate.StartCheck()
        labels.removeAll()
        if countsAreUnavailable {
            countsAreUnavailable = false
        }
        refreshBadges()
    }

    /// Brings the items and the reader in line with the inputs: nothing while the badges are not
    /// active or the read switched itself off, the items while they are, and the reader while an
    /// item can be seen and the Mac is in use.
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
        let visibility = visibilityInputs()
        appItems.apply(visibility: visibility)
        feed(visibility)
        // The chosen apps changed while the reader runs: it reads again, for the new ones.
        if dockObserver != nil, passApps != apps {
            unregisterReader()
            registerReader()
        }
    }

    /// Creates the items and starts following where they stand.
    private func makeItems() -> DockBadgeItems {
        visibilityLoop = ObservationLoop.observe { [weak self] in
            self?.visibilityInputs() ?? DockBadgeVisibility.Inputs()
        } onChange: { [weak self] inputs in
            self?.items?.apply(visibility: inputs)
            self?.feed(inputs)
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

    /// Takes the items out, keeping their places, and ends the reader.
    private func stopBadges() {
        stopReader()
        visibilityLoop?.cancel()
        visibilityLoop = nil
        items?.removeAll(keepingPosition: true)
        items = nil
        labels.removeAll()
    }

    // MARK: Reader

    /// Whether an item can be seen and the Mac is in use feeds the visibility rule, which says when
    /// the reader exists. An item that is only hidden by the zero mode Hide is in a shown section
    /// all the same, so it counts: otherwise Hide at zero everywhere would stop the reader and the
    /// badges could never come back.
    private func feed(_ inputs: DockBadgeVisibility.Inputs) {
        apply(.paused(inputs.isPaused))
        apply(.shown(inputs.hasShownItem))
    }

    /// Feeds an event to the visibility rule and does what it says.
    private func apply(_ event: ReadoutVisibility.Event) {
        switch readVisibility.handle(event, at: .now) {
        case .keep:
            break
        case .register:
            settleTask?.cancel()
            settleTask = nil
            registerReader()
        case .unregister:
            settleTask?.cancel()
            settleTask = nil
            unregisterReader()
        case .waitUntil(let instant):
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                do {
                    try await Task.sleep(until: instant, clock: ContinuousClock())
                } catch {
                    return
                }
                self?.apply(.settleElapsed)
            }
        }
    }

    /// Creates the observer of the Dock and of the chosen apps and reads once.
    private func registerReader() {
        guard dockObserver == nil, let appState else {
            return
        }
        let observer = DockObserver()
        dockObserver = observer
        observer.start { [weak self] in
            self?.dockDidNotify()
        }
        passApps = appState.settings.dockBadges.apps
        startWorkspaceObservation()
        arm(refresh.visible(true, at: .now))
        syncRefreshState()
    }

    /// Ends the observer, the observations, the wait and the pass that runs. The refresh keeps
    /// whether the Dock could not be read.
    private func unregisterReader() {
        guard let observer = dockObserver else {
            return
        }
        observer.stop()
        dockObserver = nil
        for task in workspaceTasks {
            task.cancel()
        }
        workspaceTasks = []
        passGeneration &+= 1
        passTask?.cancel()
        passTask = nil
        passApps = []
        arm(refresh.visible(false, at: .now))
        syncRefreshState()
    }

    /// Ends the reader for good and forgets what it had learned: the next one begins afresh.
    private func stopReader() {
        settleTask?.cancel()
        settleTask = nil
        readVisibility = ReadoutVisibility()
        unregisterReader()
        refresh = DockBadgeRefresh()
        syncRefreshState()
    }

    /// Follows the chosen apps being activated, launched or quit (the Dock changes the badge a
    /// moment later), and the Dock itself launching or quitting.
    private func startWorkspaceObservation() {
        guard workspaceTasks.isEmpty else {
            return
        }
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            workspaceTasks.append(Task { [weak self] in
                for await notification in center.notifications(named: name) {
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    self?.appDidChange(app?.bundleIdentifier, notification: name)
                }
            })
        }
    }

    private func appDidChange(_ bundleID: String?, notification name: Notification.Name) {
        guard let observer = dockObserver, let bundleID, let appState else {
            return
        }
        if bundleID == DockReader.bundleIdentifier {
            // A Dock that restarts is a new process with new elements.
            if name == NSWorkspace.didLaunchApplicationNotification {
                observer.dockDidLaunch()
                arm(refresh.activated(at: .now))
            } else if name == NSWorkspace.didTerminateApplicationNotification {
                observer.dockDidQuit()
            }
            return
        }
        guard appState.settings.dockBadges.isChosen(bundleID) else {
            return
        }
        arm(refresh.activated(at: .now))
    }

    /// The Dock posted a notification: only the fact counts.
    private func dockDidNotify() {
        guard dockObserver != nil else {
            return
        }
        arm(refresh.notified(at: .now))
    }

    /// Brings the one wait to what the refresh says.
    private func arm(_ action: DockBadgeRefresh.Action) {
        switch action {
        case .none:
            break
        case .stop:
            waitTask?.cancel()
            waitTask = nil
        case .readAt(let instant):
            waitTask?.cancel()
            // A far wait may be late by a few seconds, a near one by a tenth of a second.
            let delay: Duration = instant - ContinuousClock.now
            let tolerance: Duration = delay > .seconds(10) ? .seconds(3) : .milliseconds(100)
            waitTask = Task { [weak self] in
                do {
                    try await Task.sleep(until: instant, tolerance: tolerance, clock: ContinuousClock())
                } catch {
                    return
                }
                self?.waitDidEnd()
            }
        }
    }

    /// The wait is over: runs the pass that is due.
    private func waitDidEnd() {
        guard dockObserver != nil, let trigger = refresh.fire(at: .now) else {
            return
        }
        let generation = passGeneration
        passTask = Task { [weak self] in
            await self?.runPass(trigger: trigger, generation: generation)
        }
    }

    /// Makes the settings follow the refresh.
    private func syncRefreshState() {
        if refreshPolls != refresh.showsPollingLine {
            refreshPolls = refresh.showsPollingLine
        }
        if readerFailed != refresh.readerFailed {
            readerFailed = refresh.readerFailed
        }
    }

    // MARK: Pass

    /// Reads one pass over the Dock, acts on it, and tells the refresh how it went.
    private func runPass(trigger: DockBadgeRefresh.Trigger, generation: Int) async {
        guard generation == passGeneration, let settings = appState?.settings.dockBadges else {
            return
        }
        let result = await DockReader.labels(of: Set(settings.apps), readsLabels: gate?.isAvailable ?? true)
        // A pass that finishes after something changed neither counts nor shows.
        guard !Task.isCancelled, generation == passGeneration else {
            return
        }
        let before = labels
        handle(result, settings: settings)
        guard generation == passGeneration else {
            return
        }
        let failed = !result.pass.dockReadable
        let changed = !failed && DockBadgeRefresh.changed(from: before, to: labels)
        arm(refresh.passFinished(trigger: trigger, changed: changed, failed: failed, at: .now))
        syncRefreshState()
    }

    /// Acts on a pass: the start check until it decides, then the gate's success or failure, and
    /// the items' badges while the read is available.
    private func handle(_ result: DockReader.LabelPass, settings: DockBadgesSettings) {
        if gate == nil {
            guard let load = startCheck.record(result.pass) else {
                return
            }
            gate = PrivateFeatureGate(isEnabled: true, load: load)
        }
        if gate?.isAvailable == true {
            switch DockLabelGate.outcome(result.pass, interfaceProven: true) {
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
