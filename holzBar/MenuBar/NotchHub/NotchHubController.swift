//
//  NotchHubController.swift
//  holzBar
//

import AppKit
import Observation
import OSLog
import SwiftUI

/// The Notch hub module's controller: it follows the module switch, and opens and closes the
/// hub's panel.
///
/// Nothing exists while the module is off except the observation of the switch: no panel, no
/// monitor and no task. The panel is created the first time the hub opens, and released when
/// the module goes off.
///
/// The hub opens when the pointer rests at the notch (or at the top centre of a display
/// without one) and when the hotkey asks. What may open it is decided by ``NotchHubPolicy``;
/// this class reads the environment once, when the hub would open, and never follows it. Three
/// kinds of things exist only while they are needed:
///
/// - the hover monitor, its zones and its one-shot tasks, while the hub is on and Open on
///   hover is on, or while a hub that a file drag opened is open;
/// - the drag monitor, which tells a file dragged to the notch from other mouse drags
///   (``FileDragWatch``), while the hub is on and a module accepts file drags; it shares the
///   zones and the one-shot tasks of the hover;
/// - the click monitor and the two change tasks, while the hub is open;
/// - a module's runtime, while the hub and the module are both on (``HubModuleLifecycle``);
/// - the compact capsule of the live activities, its two change tasks and its place in the
///   hover zone, while at least one activity is live and the hub is closed.
///
/// Every wait is a one-shot task; there is no timer. The only wait the live activities own is
/// one task until the next finished activity leaves, armed only while one exists.
@MainActor
@Observable
final class NotchHubController: HubHost {
    /// The identifier of the module in ``ModuleCatalog``.
    static let moduleID = "notch-hub"

    /// Whether the module is on.
    private(set) var isActive = false

    /// Whether the hub is open.
    private(set) var isOpen = false

    /// What the hub's views read: the runtimes, the strip and the selected tab.
    let model = NotchHubModel()

    /// The display the hub is open on, or `nil` while it is closed.
    var screenID: CGDirectDisplayID? {
        openScreenID
    }

    @ObservationIgnored private let logger = Logger(category: "NotchHub")
    @ObservationIgnored private weak var appState: AppState?

    /// Follows the module switch; the only observation that exists while the module is off.
    @ObservationIgnored private var moduleLoop: ObservationLoop?

    /// Follows which hub modules are switched on, while the hub is on.
    @ObservationIgnored private var modulesLoop: ObservationLoop?

    /// Follows the hub's own settings, while the hub is on.
    @ObservationIgnored private var settingsLoop: ObservationLoop?

    /// Follows the live activities and what decides whether the capsule may show, while the hub
    /// is on.
    @ObservationIgnored private var activitiesLoop: ObservationLoop?

    /// Follows whether a module accepts file drags, while the hub is on.
    @ObservationIgnored private var dragLoop: ObservationLoop?

    /// The runtimes of the hub modules that are on, by identifier. Empty while the hub is off.
    @ObservationIgnored private var runtimes = [String: any HubModuleRuntime]()

    /// The panel, created by the first open and released when the module goes off.
    @ObservationIgnored private var panel: NotchHubPanel?

    @ObservationIgnored private var openScreenID: CGDirectDisplayID?

    /// What opened the hub, while it is open.
    @ObservationIgnored private var openedBy: NotchHubPolicy.Trigger?

    // MARK: Hover

    /// The hover zone of a display and where the display is.
    private struct Zone {
        var frame: CGRect
        var hoverZone: NotchHubGeometry.Rect
        /// The compact capsule's rectangle while it shows on this display: the pointer resting
        /// on it asks for the hub like the pointer at the notch.
        var compactZone: NotchHubGeometry.Rect?
    }

    /// What decides whether the hover monitor and its zones exist.
    private struct HoverConfiguration: Equatable {
        var opensOnHover: Bool
        var displays: NotchHubDisplays
    }

    /// Reports the pointer's moves, while the hub and Open on hover are on.
    @ObservationIgnored private var hoverMonitor: EventMonitor?

    /// The hover zones by display, built only for the displays the setting includes.
    @ObservationIgnored private var zones = [CGDirectDisplayID: Zone]()

    /// Follows the displays, to build the zones again.
    @ObservationIgnored private var zoneTask: Task<Void, Never>?

    /// Keeps at most one delayed hover action pending.
    @ObservationIgnored private var hoverSchedule = HoverSchedule<NotchHubPolicy.HoverAction>()

    /// The one-shot wait of the pending hover action.
    @ObservationIgnored private var hoverTask: Task<Void, Never>?

    /// Whether the pointer has been outside the zone since the hub last closed, so that a hub
    /// closed by Esc, the hotkey or a click does not open again under the resting pointer.
    @ObservationIgnored private var hoverIsArmed = true

    // MARK: File drags

    /// Reports mouse presses, drags and releases in other apps, while the hub is on and a module
    /// accepts file drags. It reads mouse events only, which need no permission.
    @ObservationIgnored private var dragMonitor: EventMonitor?

    /// Decides which drags are file drags; exists with the drag monitor.
    @ObservationIgnored private var dragWatch: FileDragWatch?

    /// The pasteboard of drags; only its change count and, once per drag, whether it can give file
    /// URLs are read, never a name, a path or any content.
    @ObservationIgnored private var dragPasteboard: NSPasteboard?

    /// Whether the pending open or close is a file drag's. A drag that asks for nothing cancels
    /// only its own pending action, never one the hover started.
    @ObservationIgnored private var dragOwnsPending = false

    // MARK: While open

    /// Closes the hub on a click outside holzBar's windows. AppKit never reports a click in the
    /// hub or another window of holzBar to a global monitor.
    @ObservationIgnored private var outsideClickMonitor: EventMonitor?

    @ObservationIgnored private var openTasks = [Task<Void, Never>]()

    // MARK: While the capsule shows

    /// What the board of live activities is built from, and what decides whether the capsule
    /// may show: the activities, a fullscreen space and a menu bar the system hides.
    private struct ActivityInputs: Equatable {
        var activities: [LiveActivity]
        var isFullscreenSpace: Bool
        var isMenuBarHidden: Bool
    }

    /// Where the capsule is while it shows.
    private struct CompactPlacement {
        var screenID: CGDirectDisplayID
        var hoverZone: NotchHubGeometry.Rect
    }

    /// The width the capsule asks the geometry for; the geometry keeps it within its limits.
    private static let compactContentWidth: Double = 240

    @ObservationIgnored private var compactPlacement: CompactPlacement?
    @ObservationIgnored private var compactHostingView: NotchHubCompactHostingView?

    /// The two tasks that follow space and display changes, only while the capsule shows.
    @ObservationIgnored private var compactTasks = [Task<Void, Never>]()

    /// The one wait of the live activities: until the next finished activity leaves.
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var expiryGeneration = 0

    // MARK: Setup

    /// Follows the module switch. With the module off, nothing else is created.
    func performSetup(with appState: AppState) {
        self.appState = appState
        moduleLoop = ObservationLoop.observe { [weak appState] in
            appState?.modules.isEnabled(Self.moduleID) ?? false
        } onChange: { [weak self] isOn in
            self?.setActive(isOn)
        }
        setActive(appState.modules.isEnabled(Self.moduleID))
    }

    private func setActive(_ isOn: Bool) {
        guard isOn != isActive else {
            return
        }
        isActive = isOn
        if isOn {
            modulesLoop = ObservationLoop.observe { [weak appState] in
                guard let appState else {
                    return Set<String>()
                }
                return Set(HubModules.all.map(\.id).filter { appState.modules.isEnabled($0) })
            } onChange: { [weak self] _ in
                self?.reconcileRuntimes()
            }
            settingsLoop = ObservationLoop.observe { [weak appState] in
                guard let settings = appState?.settings.notchHub else {
                    return HoverConfiguration(opensOnHover: false, displays: .all)
                }
                return HoverConfiguration(opensOnHover: settings.opensOnHover, displays: settings.displays)
            } onChange: { [weak self] _ in
                self?.updateHover()
            }
            activitiesLoop = ObservationLoop.observe { [weak self] in
                self?.activityInputs() ?? ActivityInputs(activities: [], isFullscreenSpace: false, isMenuBarHidden: false)
            } onChange: { [weak self] _ in
                self?.activitiesDidChange()
            }
            reconcileRuntimes()
            updateHover()
            activitiesDidChange()
        } else {
            modulesLoop = nil
            dragLoop = nil
            settingsLoop = nil
            activitiesLoop = nil
            cancelExpiry()
            hideCompact()
            stopHover()
            close()
            // The hub is off, so the plan stops every runtime before the panel goes.
            reconcileRuntimes()
            panel?.orderOut(nil)
            panel = nil
        }
    }

    /// The running runtime of a module, or `nil` while the hub or that module is off. It is how a
    /// module's settings read its state. It creates nothing and starts nothing; it reads the
    /// model's list of the runtimes that ``reconcileRuntimes()`` keeps, so a view that calls it
    /// updates when a runtime starts or stops.
    func runtime<T: HubModuleRuntime>(_ type: T.Type) -> T? {
        for runtime in model.runtimes {
            if let match = runtime as? T {
                return match
            }
        }
        return nil
    }

    /// Starts and stops the runtimes the plan says: a module has one only while the hub and the
    /// module are both on.
    private func reconcileRuntimes() {
        guard let appState else {
            return
        }
        let registered = HubModuleLifecycle.registeredOrder(
            catalogOrder: ModuleCatalog.all.map(\.id),
            registrations: HubModules.all.map(\.id)
        )
        let plan = HubModuleLifecycle.plan(
            hubIsOn: isActive,
            enabled: Set(registered.filter { appState.modules.isEnabled($0) }),
            registered: registered,
            running: Set(runtimes.keys)
        )
        for id in plan.stop {
            runtimes.removeValue(forKey: id)?.shutDown()
        }
        for id in plan.start {
            if let runtime = HubModules.registration(for: id)?.makeRuntime(appState) {
                runtimes[id] = runtime
            }
        }
        // The model follows the runtimes in catalog order. An unchanged list is not stored,
        // so the views do not draw again for it.
        let ordered = registered.compactMap { runtimes[$0] }
        if ordered.map(\.moduleID) != model.runtimes.map(\.moduleID) {
            model.runtimes = ordered
        }
        followFileDrags()
        updateDragWatching()
    }

    /// Follows whether a module accepts file drags. It starts again whenever the runtimes change,
    /// because what it reads is the setting of the runtimes that exist.
    private func followFileDrags() {
        guard isActive else {
            dragLoop = nil
            return
        }
        dragLoop = ObservationLoop.observe { [weak self] in
            self?.acceptsFileDrags() ?? false
        } onChange: { [weak self] _ in
            self?.updateDragWatching()
        }
    }

    // MARK: Opening and closing

    /// Opens the hub, or closes it, for the hotkey. Does nothing while the module is off.
    func toggle() {
        guard isActive else {
            return
        }
        if isOpen {
            close()
        } else {
            open(on: preferredScreen(), trigger: .hotkey)
        }
    }

    /// The display the hotkey opens the hub on, and the capsule shows on: the one under the
    /// pointer when the setting includes it, else the first one it includes.
    private func preferredScreen() -> NSScreen? {
        if let screen = NSScreen.screenWithMouse, isIncluded(screen) {
            return screen
        }
        return NSScreen.screens.first { isIncluded($0) }
    }

    private func isIncluded(_ screen: NSScreen) -> Bool {
        guard let displays = appState?.settings.notchHub.displays else {
            return false
        }
        return displays.includes(isBuiltIn: CGDisplayIsBuiltin(screen.displayID) != 0, hasNotch: screen.hasNotch)
    }

    /// Opens the hub on a screen, unless the policy says it must not open or the screen has no
    /// usable size.
    private func open(on screen: NSScreen?, trigger: NotchHubPolicy.Trigger) {
        guard
            isActive,
            !isOpen,
            let appState,
            let screen
        else {
            return
        }
        // Read once, now, and never followed.
        let environment = policyEnvironment(of: screen, appState: appState)
        if let reason = NotchHubPolicy.blockReason(environment, trigger: trigger) {
            logger.debug("The Notch hub stays closed: \(reason.rawValue, privacy: .public)")
            return
        }
        guard
            let layout = NotchHubGeometry.layout(
                display: Self.display(of: screen),
                content: NotchHubGeometry.Content(bodyHeight: NotchHubGeometry.bodyHeight)
            )
        else {
            logger.debug("The Notch hub has no layout for this screen")
            return
        }
        // The capsule and the hub are one panel: the capsule goes first.
        hideCompact()
        if trigger == .fileDrag {
            showDropTab()
        }
        let panel = panel ?? NotchHubPanel()
        self.panel = panel
        let flipped = NotchHubGeometry.flipped(layout.silhouette, displayHeight: Double(screen.frame.height))
        panel.applyDarkAppearance()
        panel.acceptsKeyboard = trigger == .hotkey
        panel.onEscape = { [weak self] in
            self?.close()
        }
        panel.contentView = NotchHubHostingView(
            view: NotchHubView(layout: layout, model: model, host: self, takesKeyboard: trigger == .hotkey)
        )
        panel.setFrame(
            NSRect(
                x: screen.frame.minX + flipped.x,
                y: screen.frame.minY + flipped.y,
                width: flipped.width,
                height: flipped.height
            ),
            display: true
        )
        panel.orderFrontRegardless()
        if trigger == .hotkey {
            panel.makeKey()
        }
        isOpen = true
        openedBy = trigger
        openScreenID = screen.displayID
        dragWatch?.hubOpened(byDrag: trigger == .fileDrag)
        if trigger == .fileDrag {
            // The hub a drag opened closes when the pointer leaves it, even without Open on hover.
            updateHover()
        }
        startOpenObservers()
        notifyRuntimes(isOpen: true)
        logger.debug("The Notch hub opened on display \(screen.displayID, privacy: .public)")
    }

    /// Closes the hub. The panel stays for the next open, without content.
    func close() {
        guard isOpen else {
            return
        }
        stopOpenObservers()
        cancelHover()
        // The pointer may rest in the zone; the hub opens again only after it left.
        hoverIsArmed = false
        panel?.acceptsKeyboard = false
        panel?.onEscape = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        let wasOpenedByDrag = openedBy == .fileDrag
        isOpen = false
        openedBy = nil
        openScreenID = nil
        dragWatch?.hubClosed()
        if wasOpenedByDrag {
            updateHover()
        }
        notifyRuntimes(isOpen: false)
        // The capsule comes back when something is live.
        activitiesDidChange()
    }

    private func notifyRuntimes(isOpen: Bool) {
        for runtime in model.runtimes {
            runtime.hubVisibilityDidChange(isOpen: isOpen)
        }
    }

    // MARK: While open

    /// Starts what closes the hub: a click outside, a change of space and a change of displays.
    private func startOpenObservers() {
        stopOpenObservers()
        let monitor = EventMonitor.global(for: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.close()
        }
        monitor.start()
        outsideClickMonitor = monitor
        openTasks = [
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                    self?.close()
                }
            },
            Task { [weak self] in
                let center = NotificationCenter.default
                for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                    self?.close()
                }
            },
        ]
    }

    private func stopOpenObservers() {
        outsideClickMonitor?.stop()
        outsideClickMonitor = nil
        for task in openTasks {
            task.cancel()
        }
        openTasks.removeAll()
    }

    // MARK: Hover

    /// Starts the hover monitor and builds the zones while the hub and Open on hover are on,
    /// and removes them otherwise.
    private func updateHover() {
        guard isActive, wantsHover else {
            stopHover()
            return
        }
        updateZones()
        guard hoverMonitor == nil else {
            return
        }
        let monitor = EventMonitor.passive(for: .mouseMoved, scope: .universal) { [weak self] _ in
            self?.pointerMoved()
        }
        monitor.start()
        hoverMonitor = monitor
    }

    private func stopHover() {
        hoverMonitor?.stop()
        hoverMonitor = nil
        cancelHover()
        updateZones()
    }

    /// Whether the hover monitor is wanted: Open on hover is on, or the hub a file drag opened is
    /// open and has to close when the pointer leaves it.
    private var wantsHover: Bool {
        appState?.settings.notchHub.opensOnHover == true || (isOpen && openedBy == .fileDrag)
    }

    /// Builds the zones and follows the displays while the hover or the drag watch needs them, and
    /// releases both otherwise. The one cache serves both.
    private func updateZones() {
        guard isActive, wantsHover || dragMonitor != nil else {
            zoneTask?.cancel()
            zoneTask = nil
            zones.removeAll()
            return
        }
        buildZones()
        guard zoneTask == nil else {
            return
        }
        zoneTask = Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.buildZones()
            }
        }
    }

    private func cancelHover() {
        dragOwnsPending = false
        hoverTask?.cancel()
        hoverTask = nil
        hoverSchedule.cancel()
    }

    /// Works out the hover zone of each display the setting includes. Done when hover starts
    /// and when the displays change, never on a pointer move.
    private func buildZones() {
        zones.removeAll()
        for screen in NSScreen.screens where isIncluded(screen) {
            guard
                let layout = NotchHubGeometry.layout(
                    display: Self.display(of: screen),
                    content: NotchHubGeometry.Content(bodyHeight: NotchHubGeometry.bodyHeight)
                )
            else {
                continue
            }
            zones[screen.displayID] = Zone(frame: screen.frame, hoverZone: layout.hoverZone)
        }
        if let placement = compactPlacement {
            zones[placement.screenID]?.compactZone = placement.hoverZone
        }
    }

    /// Where the pointer is, from the cached zones: one rectangle test per display, no layout.
    /// Also the display of the zone it is in.
    private func pointerPlacement() -> (pointer: NotchHubPolicy.Pointer, zoneScreenID: CGDirectDisplayID?) {
        let location = NSEvent.mouseLocation
        var pointer = NotchHubPolicy.Pointer(isInZone: false, isInHub: false)
        var zoneScreenID: CGDirectDisplayID?
        for (id, zone) in zones where Self.contains(zone.frame, location) {
            // While the hub is open, only the zone of the display it is open on counts.
            if isOpen, id != openScreenID {
                continue
            }
            let local = NotchHubPolicy.localPoint(
                globalX: Double(location.x),
                globalY: Double(location.y),
                displayMinX: Double(zone.frame.minX),
                displayMaxY: Double(zone.frame.maxY)
            )
            let isInHubZone = zone.hoverZone.contains(x: local.x, y: local.y)
            let isInCompactZone = zone.compactZone?.contains(x: local.x, y: local.y) ?? false
            if isInHubZone || isInCompactZone {
                pointer.isInZone = true
                zoneScreenID = id
            }
        }
        if isOpen, let panel {
            pointer.isInHub = Self.contains(panel.frame, location)
        }
        return (pointer, zoneScreenID)
    }

    /// Handles a move of the pointer: one rectangle test against the cached zones, and a
    /// decision only when the answer changes.
    private func pointerMoved() {
        var (pointer, zoneScreenID) = pointerPlacement()
        if !pointer.isInZone {
            hoverIsArmed = true
        } else if !hoverIsArmed, !isOpen {
            pointer.isInZone = false
        }
        let decision = NotchHubPolicy.hoverDecision(
            pointer: pointer,
            isOpen: isOpen,
            closesOnLeave: openedBy?.closesOnLeave ?? false,
            pending: hoverSchedule.pending
        )
        switch decision {
        case .none:
            return
        case .cancelPending:
            cancelHover()
        case .schedule(let action):
            schedule(action, screenID: zoneScreenID)
        }
    }

    /// Waits for the delay of the action in one task, then performs it.
    private func schedule(
        _ action: NotchHubPolicy.HoverAction,
        screenID: CGDirectDisplayID?,
        trigger: NotchHubPolicy.Trigger = .hover
    ) {
        guard let generation = hoverSchedule.request(action) else {
            return
        }
        hoverTask?.cancel()
        dragOwnsPending = trigger == .fileDrag
        let delay = action == .open ? NotchHubPolicy.openDelay : NotchHubPolicy.closeDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            self?.performHover(action, generation: generation, screenID: screenID, trigger: trigger)
        }
    }

    private func performHover(
        _ action: NotchHubPolicy.HoverAction,
        generation: Int,
        screenID: CGDirectDisplayID?,
        trigger: NotchHubPolicy.Trigger
    ) {
        hoverSchedule.finish(generation)
        hoverTask = nil
        dragOwnsPending = false
        switch action {
        case .open:
            // A drag that ended during the dwell opens nothing.
            if trigger == .fileDrag, NSEvent.pressedMouseButtons & 1 == 0 {
                return
            }
            open(on: NSScreen.screens.first { $0.displayID == screenID }, trigger: trigger)
        case .close:
            close()
        }
    }

    // MARK: File drags

    /// Whether a running module accepts file drags.
    private func acceptsFileDrags() -> Bool {
        runtimes.values.contains { $0.acceptsFileDrags }
    }

    /// Starts the drag monitor and the watch while the hub is on and a module accepts file
    /// drags, and releases both, and the zones when nothing else needs them, otherwise.
    private func updateDragWatching() {
        guard isActive, acceptsFileDrags() else {
            guard dragMonitor != nil else {
                return
            }
            dragMonitor?.stop()
            dragMonitor = nil
            dragWatch = nil
            dragPasteboard = nil
            cancelHover()
            updateZones()
            return
        }
        guard dragMonitor == nil else {
            return
        }
        let pasteboard = NSPasteboard(name: .drag)
        dragPasteboard = pasteboard
        dragWatch = FileDragWatch(changeCount: pasteboard.changeCount)
        let monitor = EventMonitor.global(for: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.dragEvent(event.type)
        }
        monitor.start()
        dragMonitor = monitor
        updateZones()
    }

    /// Feeds one mouse event of another app to the watch and applies what it asks for. The cost
    /// is an integer read per event; the pasteboard is asked for file URLs once per drag, and the
    /// zones are tested only while a file drag is known. Nothing is stored or logged.
    private func dragEvent(_ type: NSEvent.EventType) {
        guard dragWatch != nil, let pasteboard = dragPasteboard else {
            return
        }
        let count = pasteboard.changeCount
        var outcome: FileDragWatch.Outcome?
        var zoneScreenID: CGDirectDisplayID?
        switch type {
        case .leftMouseDown:
            dragWatch?.pressed(changeCount: count)
        case .leftMouseDragged:
            let needsInspection = dragWatch?.needsInspection(changeCount: count) ?? false
            let hasFileURLs = needsInspection
                && pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            var pointer = NotchHubPolicy.Pointer(isInZone: false, isInHub: false)
            if hasFileURLs || dragWatch?.isFileDrag == true {
                (pointer, zoneScreenID) = pointerPlacement()
            }
            outcome = dragWatch?.dragged(
                changeCount: count,
                hasFileURLs: hasFileURLs,
                pointerInZone: pointer.isInZone,
                pointerInHub: pointer.isInHub,
                hubIsOpen: isOpen
            )
        case .leftMouseUp:
            let isInHub = isOpen && panel.map { Self.contains($0.frame, NSEvent.mouseLocation) } == true
            outcome = dragWatch?.released(hubIsOpen: isOpen, pointerInHub: isInHub)
        default:
            return
        }
        guard let outcome else {
            return
        }
        if outcome.showDropTab {
            showDropTab()
        }
        switch NotchHubPolicy.decision(
            desired: outcome.wish,
            pending: dragOwnsPending ? hoverSchedule.pending : nil
        ) {
        case .none:
            return
        case .cancelPending:
            cancelHover()
        case .schedule(let action):
            schedule(action, screenID: zoneScreenID, trigger: .fileDrag)
        }
    }

    /// Shows the tab of the first module that accepts file drags.
    private func showDropTab() {
        guard let module = model.runtimes.first(where: { $0.acceptsFileDrags }),
              model.selectedID != module.moduleID
        else {
            return
        }
        select(moduleID: module.moduleID)
    }

    // MARK: Live activities

    /// What the policy needs to know about the Mac when the hub or the capsule would show: read
    /// when asked, never followed.
    private func policyEnvironment(of screen: NSScreen, appState: AppState) -> NotchHubPolicy.Environment {
        NotchHubPolicy.Environment(
            isFullscreenSpace: appState.activeSpace.isFullscreen,
            isMenuBarHiddenBySystem: appState.menuBarManager.isMenuBarHiddenBySystem,
            isPresenting: PresentationSignals.isPresenting(
                mirroredDisplays: PresentationMonitor.mirroredDisplayCount(),
                runningBundleIDs: PresentationMonitor.runningBundleIDs()
            ),
            isDisplayAllowed: isIncluded(screen)
        )
    }

    /// Reads, in one place, what the capsule depends on, so that the loop follows each of them.
    private func activityInputs() -> ActivityInputs {
        ActivityInputs(
            activities: model.activities,
            isFullscreenSpace: appState?.activeSpace.isFullscreen ?? false,
            isMenuBarHidden: appState?.menuBarManager.isMenuBarHiddenBySystem ?? false
        )
    }

    /// Works out the board and shows, moves or hides the capsule. Called when an activity
    /// changes, when a fullscreen space or the hidden menu bar changes, when the hub closes,
    /// when a finished activity leaves and when a space or the displays change while the
    /// capsule shows.
    ///
    /// The capsule shows only while an activity is live, the hub is closed and the policy lets
    /// the hub open on the display.
    private func activitiesDidChange() {
        guard isActive else {
            hideCompact()
            return
        }
        let board = model.board(now: .now)
        armExpiry(at: board.nextExpiry)
        guard
            board.compact != nil,
            !isOpen,
            let appState,
            let screen = preferredScreen(),
            NotchHubPolicy.blockReason(policyEnvironment(of: screen, appState: appState), trigger: .compact) == nil
        else {
            hideCompact()
            return
        }
        showCompact(board: board, on: screen)
    }

    /// Hangs the capsule below the notch of the screen, or updates it where it already is. The
    /// capsule is the hub's panel in a smaller frame: no second window exists.
    private func showCompact(board: HubActivityBoard.Board, on screen: NSScreen) {
        guard
            let layout = NotchHubGeometry.compactLayout(
                display: Self.display(of: screen),
                contentWidth: Self.compactContentWidth
            )
        else {
            hideCompact()
            return
        }
        let view = NotchHubCompactView(board: board) { [weak self] in
            // The click is handled after the view's own action has returned, because opening
            // the hub replaces the view.
            Task { @MainActor in
                self?.compactWasClicked()
            }
        }
        let panel = panel ?? NotchHubPanel()
        self.panel = panel
        if let hostingView = compactHostingView {
            hostingView.rootView = view
        } else {
            let hostingView = NotchHubCompactHostingView(view: view)
            compactHostingView = hostingView
            panel.applyDarkAppearance()
            panel.acceptsKeyboard = false
            panel.onEscape = nil
            panel.contentView = hostingView
            startCompactObservers()
        }
        let flipped = NotchHubGeometry.flipped(layout.silhouette, displayHeight: Double(screen.frame.height))
        panel.setFrame(
            NSRect(
                x: screen.frame.minX + flipped.x,
                y: screen.frame.minY + flipped.y,
                width: flipped.width,
                height: flipped.height
            ),
            display: true
        )
        panel.orderFrontRegardless()
        compactPlacement = CompactPlacement(screenID: screen.displayID, hoverZone: layout.hoverZone)
        zones = zones.mapValues { zone in
            var zone = zone
            zone.compactZone = nil
            return zone
        }
        zones[screen.displayID]?.compactZone = layout.hoverZone
    }

    /// Takes the capsule away and ends what exists only while it shows. Does nothing to the
    /// panel while the hub is open.
    private func hideCompact() {
        for task in compactTasks {
            task.cancel()
        }
        compactTasks.removeAll()
        guard compactPlacement != nil else {
            return
        }
        compactPlacement = nil
        compactHostingView = nil
        zones = zones.mapValues { zone in
            var zone = zone
            zone.compactZone = nil
            return zone
        }
        guard !isOpen else {
            return
        }
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    /// Follows the active space and the displays, only while the capsule shows: on either it
    /// works out again where, and whether, the capsule shows.
    private func startCompactObservers() {
        compactTasks = [
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                    self?.activitiesDidChange()
                }
            },
            Task { [weak self] in
                let center = NotificationCenter.default
                for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                    self?.activitiesDidChange()
                }
            },
        ]
    }

    /// Opens the hub on the capsule's display.
    private func compactWasClicked() {
        guard let screenID = compactPlacement?.screenID else {
            return
        }
        open(on: NSScreen.screens.first { $0.displayID == screenID }, trigger: .compact)
    }

    // MARK: The wait for an expiry

    /// Arms the one wait of the live activities: until the next finished activity leaves, then
    /// the board is worked out again. Replaces a wait already armed, and arms none when no
    /// finished activity is waiting to leave.
    private func armExpiry(at date: Date?) {
        expiryTask?.cancel()
        expiryTask = nil
        expiryGeneration += 1
        guard let date else {
            return
        }
        let generation = expiryGeneration
        expiryTask = Task { [weak self] in
            let wait = Duration.seconds(max(date.timeIntervalSinceNow, 0))
            try? await Task.sleep(until: ContinuousClock.now.advanced(by: wait), tolerance: .seconds(1))
            guard !Task.isCancelled, let self, expiryGeneration == generation else {
                return
            }
            expiryTask = nil
            model.activitiesDidExpire()
            activitiesDidChange()
        }
    }

    private func cancelExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        expiryGeneration += 1
    }

    // MARK: HubHost

    func select(moduleID: String) {
        model.select(moduleID)
    }

    func openSettings(for moduleID: String) {
        close()
        guard let appState else {
            return
        }
        appState.navigationState.settingsNavigationIdentifier = .modules
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }

    func takeKeyboard() {
        guard isOpen, let panel else {
            return
        }
        panel.acceptsKeyboard = true
        panel.makeKey()
    }

    // MARK: Geometry

    /// Whether the point is in the rectangle, all four edges included: the pointer can sit on
    /// the top edge of a display, which `CGRect.contains` leaves out.
    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// What the geometry needs to know about a screen, read from the system's own values.
    private static func display(of screen: NSScreen) -> NotchHubGeometry.Display {
        let frame = screen.frame
        let notch: NotchHubGeometry.Notch? = if screen.hasNotch {
            NotchHubGeometry.notch(
                displayWidth: Double(frame.width),
                leftAreaWidth: screen.auxiliaryTopLeftArea.map { Double($0.width) },
                rightAreaWidth: screen.auxiliaryTopRightArea.map { Double($0.width) },
                height: Double(screen.safeAreaInsets.top)
            )
        } else {
            nil
        }
        let menuBarHeight: CGFloat
        if screen.hasNotch {
            menuBarHeight = screen.safeAreaInsets.top
        } else if frame.maxY - screen.visibleFrame.maxY > 0 {
            menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        } else {
            menuBarHeight = NSStatusBar.system.thickness
        }
        return NotchHubGeometry.Display(
            width: Double(frame.width),
            height: Double(frame.height),
            menuBarHeight: Double(menuBarHeight),
            notch: notch
        )
    }
}
