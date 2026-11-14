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
/// - the click monitor, the two change tasks and the observation of the content's height, while
///   the hub is open;
/// - the late re-decision's observation and its one-second wait, only in the first second of an
///   opening (``startLateDecision(openedAt:)``);
/// - a module's runtime, while the hub and the module are both on (``HubModuleLifecycle``);
/// - the live state of the island, its two change tasks and its place in the hover zone, while
///   at least one activity is live and the hub is closed: the same shape and the same panel as the
///   open hub, widened at menu bar height beside the notch.
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

    /// Follows the live activities and what decides whether the live state may show, while the hub
    /// is on.
    @ObservationIgnored private var activitiesLoop: ObservationLoop?

    /// Follows whether a module accepts file drags, while the hub is on.
    @ObservationIgnored private var dragLoop: ObservationLoop?

    /// The runtimes of the hub modules that are on, by identifier. Empty while the hub is off.
    @ObservationIgnored private var runtimes = [String: any HubModuleRuntime]()

    /// The panel, created by the first open and released when the module goes off.
    @ObservationIgnored private var panel: NotchHubPanel?

    /// What the island in the panel shows and how it moves; it lives and goes with the panel.
    @ObservationIgnored private var presentation: IslandPresentation?

    /// The frame of the hub's panel (the open hub or the live state, which are one panel) while
    /// it is on screen, in AppKit coordinates; `nil` while it is not. The hit test of show on
    /// click reads it: a click on the hub is not a click on empty menu bar space.
    var visiblePanelFrame: CGRect? {
        guard let panel, panel.isVisible else {
            return nil
        }
        return panel.frame
    }

    @ObservationIgnored private var openScreenID: CGDirectDisplayID?

    /// What opened the hub, while it is open.
    @ObservationIgnored private var openedBy: NotchHubPolicy.Trigger?

    // MARK: The island's phase

    /// What the island is doing, decided only by ``HubIslandPhase``: every open, close and
    /// completion goes through ``send(_:)``.
    @ObservationIgnored private var phase = HubIslandPhase.State()

    /// The shape the panel rests at once the running transition has ended: the open shape while
    /// the hub opens, the live shape while something is live and the hub is closed, else the seed,
    /// the notch's rectangle.
    @ObservationIgnored private var restShape: NotchHubGeometry.Rect?

    /// The open shape while the hub is open and while a closing from it runs, so that a turn
    /// around still covers everything the island has drawn.
    @ObservationIgnored private var openShape: NotchHubGeometry.Rect?

    /// The frame of the display the island is on, for the panel's frame in AppKit's coordinates.
    @ObservationIgnored private var panelScreenFrame: CGRect?

    // MARK: Hover

    /// The hover zone of a display and where the display is.
    private struct Zone {
        var frame: CGRect
        var hoverZone: NotchHubGeometry.Rect
        /// The live shape's rectangle while it shows on this display: the pointer resting on it
        /// asks for the hub like the pointer at the notch.
        var liveZone: NotchHubGeometry.Rect?
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

    /// Follows the height the content area needs, while the hub is open: another module, or a
    /// module whose own height changes, resizes the island.
    @ObservationIgnored private var contentLoop: ObservationLoop?

    /// Follows what the context reads in the first second of an opening, so that a meeting whose
    /// events arrived late can come to the front once (D-03).
    @ObservationIgnored private var lateDecisionLoop: ObservationLoop?

    /// The one-shot wait that ends the late decision after ``HubContext/lateDecisionWindow``.
    @ObservationIgnored private var lateDecisionTask: Task<Void, Never>?

    // MARK: While the live state shows

    /// What the board of live activities is built from, and what decides whether the live state
    /// may show: the activities, a fullscreen space and a menu bar the system hides.
    private struct ActivityInputs: Equatable {
        var activities: [LiveActivity]
        var isFullscreenSpace: Bool
        var isMenuBarHidden: Bool
    }

    /// Where the live state is while it shows.
    private struct LivePlacement {
        var screenID: CGDirectDisplayID
        var layout: NotchHubGeometry.LiveLayout
    }

    @ObservationIgnored private var livePlacement: LivePlacement?

    /// The two tasks that follow space and display changes, only while the live state shows.
    @ObservationIgnored private var liveTasks = [Task<Void, Never>]()

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
            stopHover()
            close()
            model.endOpening()
            // The hub is off, so the plan stops every runtime before the panel goes.
            reconcileRuntimes()
            panel?.orderOut(nil)
            panel = nil
            presentation = nil
            // Everything is released at once; a completion that is still on its way must be stale.
            var released = HubIslandPhase.State()
            released.generation = phase.generation + 1
            phase = released
            restShape = nil
            openShape = nil
            panelScreenFrame = nil
            // After the close above, which may have set the live state's place again.
            hideLive()
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

    /// The display the hotkey opens the hub on, and the live state shows on: the one under the
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
        let display = Self.display(of: screen)
        guard
            NotchHubGeometry.island(
                display: display,
                contentHeight: DesignTokens.Island.contentHeight,
                width: DesignTokens.Island.baseWidth
            ) != nil,
            let seed = NotchHubGeometry.seed(display: display)
        else {
            logger.debug("The Notch hub has no layout for this screen")
            return
        }
        // What is in front is decided now, from what the modules hold in memory and before the
        // fit and the layout, which depend on it. Nothing is stored and nothing is logged.
        // The setting is read once, now, and nothing follows it while the hub is open.
        let showsActiveFirst = appState.settings.notchHub.showsActiveFirst
        let openedAt = Date.now
        model.beginOpening(HubContext.decide(model.contextInputs(now: openedAt, showsActiveFirst: showsActiveFirst)))
        if trigger == .fileDrag {
            // A file drag brings File drop to the front for this opening only (D-04).
            showDropTab()
        }
        // The hub widens first, the buttons step down next and the row scrolls last, for the
        // modules that are on now; the row keeps those buttons while the hub is open.
        let fit = HubModuleRow.fit(
            count: model.allTabIDs.count,
            baseWidth: DesignTokens.Island.baseWidth,
            maxWidth: min(DesignTokens.Island.maximumWidth, display.width - 2 * NotchHubGeometry.screenMargin)
        )
        // The content's height follows what is selected, which a file drag has just changed.
        guard
            let layout = NotchHubGeometry.island(
                display: display,
                contentHeight: currentContentHeight(),
                width: fit.hubWidth,
                buttonSize: fit.buttonSize
            )
        else {
            model.endOpening()
            return
        }
        // The live state and the hub are one panel: the hub grows out of the live shape, which
        // stops being a place the pointer can rest while the hub is open. Taken away only now,
        // when the hub is certain to open.
        setLivePlacement(nil)
        let panel = panel ?? NotchHubPanel()
        self.panel = panel
        let presentation = ensurePresentation()
        presentation.rowFit = fit
        presentation.rowIDs = model.allTabIDs
        presentation.openingCount &+= 1
        // A hub that opens again while it closes, or from the live state, on the same display,
        // reuses the panel and its view: it grows from the shape that is there, without a flash.
        let existing = phase.isPanelVisible && panelScreenFrame == screen.frame
            ? panel.contentView as? IslandHostingView
            : nil
        let transition = NotchHubGeometry.transitionFrame(
            from: (existing == nil ? nil : openShape ?? restShape) ?? seed,
            to: layout.shape,
            displayWidth: Double(screen.frame.width)
        )
        send(.open)
        openShape = layout.shape
        restShape = layout.shape
        panelScreenFrame = screen.frame
        panel.hasShadow = false
        panel.applyDarkAppearance()
        panel.acceptsKeyboard = trigger == .hotkey
        panel.onEscape = { [weak self] in
            self?.close()
        }
        presentation.takesKeyboard = trigger == .hotkey
        let hostingView: IslandHostingView
        if let existing {
            presentation.moveCanvas(transition)
            hostingView = existing
        } else {
            presentation.show(seed: seed, canvas: transition)
            hostingView = IslandHostingView(
                view: IslandView(presentation: presentation, model: model, host: self)
            )
            panel.contentView = hostingView
        }
        setPanelFrame(transition, on: screen.frame)
        panel.orderFrontRegardless()
        if trigger == .hotkey {
            panel.makeKey()
        }
        // Lay the shape out first, without animation, so that the opening starts from the notch
        // (or from where a closing had got to) and takes its own transaction.
        hostingView.layoutSubtreeIfNeeded()
        presentation.animateOpen(
            to: layout,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            generation: phase.generation
        ) { [weak self] generation in
            self?.islandAnimationFinished(generation)
        }
        openedBy = trigger
        openScreenID = screen.displayID
        dragWatch?.hubOpened(byDrag: trigger == .fileDrag)
        if trigger == .fileDrag {
            // The hub a drag opened closes when the pointer leaves it, even without Open on hover.
            updateHover()
        }
        // The one late re-decision starts before the modules are told, so that what they load
        // is seen. A file drag's pick and the setting off leave nothing to decide again.
        if showsActiveFirst, trigger != .fileDrag {
            startLateDecision(openedAt: openedAt)
        }
        startOpenObservers()
        notifyRuntimes(isOpen: true)
        logger.debug("The Notch hub opened on display \(screen.displayID, privacy: .public)")
    }

    /// Closes the hub: the content leaves, then the island returns into the notch. From the first
    /// frame of closing the hub behaves as closed; the panel is ordered out, and emptied, only
    /// when the animation has finished (``islandAnimationFinished(_:)``).
    func close() {
        guard isOpen else {
            return
        }
        stopOpenObservers()
        endLateDecision()
        cancelHover()
        // The pointer may rest in the zone; the hub opens again only after it left.
        hoverIsArmed = false
        panel?.acceptsKeyboard = false
        panel?.onEscape = nil
        let wasOpenedByDrag = openedBy == .fileDrag
        let screen = NSScreen.screens.first { $0.displayID == openScreenID }
        // The hub returns to the live state only where the live shape has a layout.
        if phase.isLive, screen.flatMap({ NotchHubGeometry.live(display: Self.display(of: $0)) }) == nil {
            send(.liveChanged(false))
        }
        send(.close)
        openedBy = nil
        openScreenID = nil
        dragWatch?.hubClosed()
        if wasOpenedByDrag {
            updateHover()
        }
        notifyRuntimes(isOpen: false)
        animateClosing(on: screen)
    }

    /// Returns the island into the notch, or, while something is live, into the live shape; when
    /// there is nothing to animate (the display is gone), ends the closing at once.
    private func animateClosing(on screen: NSScreen?) {
        guard
            let panel,
            let presentation,
            let screen,
            let seed = NotchHubGeometry.seed(display: Self.display(of: screen)),
            let from = openShape ?? restShape
        else {
            if phase.target == .live {
                // Nothing can be drawn for the live state either.
                send(.liveChanged(false))
            }
            setLivePlacement(nil)
            restShape = nil
            islandAnimationFinished(phase.generation)
            return
        }
        let live = phase.target == .live ? NotchHubGeometry.live(display: Self.display(of: screen)) : nil
        let rest = live?.shape ?? seed
        let transition = NotchHubGeometry.transitionFrame(
            from: from,
            to: rest,
            displayWidth: Double(screen.frame.width)
        )
        restShape = rest
        panelScreenFrame = screen.frame
        panel.hasShadow = false
        presentation.moveCanvas(transition)
        setPanelFrame(transition, on: screen.frame)
        // Take the larger canvas in its own transaction before the closing animates.
        panel.contentView?.layoutSubtreeIfNeeded()
        if let live {
            // The hub closes into the live state: what it will show is ready when it has settled.
            presentation.liveLayout = live
            presentation.liveBoard = model.board(now: .now)
            setLivePlacement(LivePlacement(screenID: screen.displayID, layout: live))
        }
        presentation.animateClose(
            to: rest,
            topRadius: live == nil ? DesignTokens.Island.notchTopRadius : DesignTokens.Island.liveTopRadius,
            bottomRadius: live == nil ? DesignTokens.Island.notchBottomRadius : DesignTokens.Island.liveBottomRadius,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            generation: phase.generation
        ) { [weak self] generation in
            self?.islandAnimationFinished(generation)
        }
    }

    /// Applies an event to the island's phase and mirrors what the rest of the controller reads.
    /// Returns whether the state changed: a completion that changes nothing is a stale one.
    @discardableResult
    private func send(_ event: HubIslandPhase.Event) -> Bool {
        let next = HubIslandPhase.reduce(phase, event)
        guard next != phase else {
            return false
        }
        phase = next
        if isOpen != next.isOpen {
            isOpen = next.isOpen
        }
        return true
    }

    /// The end of a transition: the panel becomes exactly the shape it rests at, the window's
    /// shadow comes back for the settled open shape, the live content shows on a settled live
    /// shape, and a closed island's panel is ordered out and emptied. A completion of a transition
    /// that a newer one replaced does nothing.
    private func islandAnimationFinished(_ generation: Int) {
        guard send(.animationFinished(generation: generation)) else {
            return
        }
        if !phase.isOpen {
            // The hub has closed: what the opening had in front is over.
            model.endOpening()
        }
        guard let panel else {
            return
        }
        if phase.ordersOut {
            panel.orderOut(nil)
            panel.contentView = nil
            openShape = nil
            // What the policy reads when asked may have changed while the hub was shown.
            activitiesDidChange()
            return
        }
        if let shape = restShape, let screenFrame = panelScreenFrame {
            presentation?.moveCanvas(shape)
            setPanelFrame(shape, on: screenFrame)
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        if phase.hasShadow {
            panel.hasShadow = true
            panel.invalidateShadow()
        }
        if phase.target == .live {
            // The hub has closed into the live state: its parts are gone and the live content
            // shows. The display may have changed while the hub was open.
            openShape = nil
            presentation?.settleLive(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            activitiesDidChange()
        }
    }

    /// Sets the panel's frame from a rectangle in the display's coordinates.
    private func setPanelFrame(_ shape: NotchHubGeometry.Rect, on screenFrame: CGRect) {
        let flipped = NotchHubGeometry.flipped(shape, displayHeight: Double(screenFrame.height))
        panel?.setFrame(
            NSRect(
                x: screenFrame.minX + flipped.x,
                y: screenFrame.minY + flipped.y,
                width: flipped.width,
                height: flipped.height
            ),
            display: true
        )
    }

    private func notifyRuntimes(isOpen: Bool) {
        for runtime in model.runtimes {
            runtime.hubVisibilityDidChange(isOpen: isOpen)
        }
    }

    // MARK: While open

    /// The height the content area needs for what is selected: the module's own, between the
    /// standard height and the largest, or the Overview's rows of cards.
    private func currentContentHeight() -> Double {
        NotchHubGeometry.contentHeight(
            overviewTileCount: model.selectedRuntime == nil ? model.tiles.count : nil,
            preferred: model.selectedRuntime?.preferredContentHeight
        )
    }

    /// The content's height changed while the hub is open: the island is laid out again at the
    /// same width and the shape's lower edge springs to the new height. The panel takes a frame
    /// that covers the old shape and the new one, so that a spring's overshoot is never clipped;
    /// when the animation has settled the panel is exactly the new shape (``islandAnimationFinished(_:)``).
    private func contentHeightDidChange() {
        guard
            isOpen,
            let panel,
            let presentation,
            let screen = NSScreen.screens.first(where: { $0.displayID == openScreenID }),
            let from = openShape ?? restShape,
            let layout = NotchHubGeometry.island(
                display: Self.display(of: screen),
                contentHeight: currentContentHeight(),
                width: presentation.rowFit.hubWidth,
                buttonSize: presentation.rowFit.buttonSize
            ),
            layout.shape != from
        else {
            return
        }
        let transition = NotchHubGeometry.transitionFrame(
            from: from,
            to: layout.shape,
            displayWidth: Double(screen.frame.width)
        )
        send(.resize)
        openShape = layout.shape
        restShape = layout.shape
        panel.hasShadow = false
        presentation.moveCanvas(transition)
        setPanelFrame(transition, on: screen.frame)
        // Take the larger canvas in its own transaction before the shape animates.
        panel.contentView?.layoutSubtreeIfNeeded()
        presentation.animateResize(
            to: layout,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            generation: phase.generation
        ) { [weak self] generation in
            self?.islandAnimationFinished(generation)
        }
    }

    /// Starts what closes the hub: a click outside, a change of space and a change of displays,
    /// and what follows the content's height.
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
        contentLoop = ObservationLoop.observe { [weak self] in
            self?.currentContentHeight() ?? DesignTokens.Island.contentHeight
        } onChange: { [weak self] _ in
            self?.contentHeightDidChange()
        }
    }

    private func stopOpenObservers() {
        contentLoop = nil
        outsideClickMonitor?.stop()
        outsideClickMonitor = nil
        for task in openTasks {
            task.cancel()
        }
        openTasks.removeAll()
    }

    // MARK: The late decision

    /// Watches what the context reads for ``HubContext/lateDecisionWindow`` seconds after an
    /// opening (D-03): the Calendar reads its events only while the hub is open, so they can arrive
    /// a moment after it. When the context then decides on a meeting and nothing was picked, the
    /// meeting comes to the front once. It is one observation and one one-shot wait, both gone
    /// after one second at most; nothing is polled and nothing is read while the hub is closed.
    ///
    /// The content switches as it does for a user's pick: it cross-fades, and the island follows
    /// the new content's height (``startOpenObservers()``).
    private func startLateDecision(openedAt: Date) {
        endLateDecision()
        let model = model
        lateDecisionLoop = ObservationLoop.observe {
            model.contextInputs(now: openedAt, showsActiveFirst: true)
        } onChange: { [weak self] inputs in
            self?.contextDidChange(inputs, openedAt: openedAt)
        }
        lateDecisionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HubContext.lateDecisionWindow))
            guard !Task.isCancelled else {
                return
            }
            self?.endLateDecision()
        }
    }

    /// The context's inputs changed in the first second: decides once more.
    private func contextDidChange(_ inputs: HubContext.Inputs, openedAt: Date) {
        let elapsed = Date.now.timeIntervalSince(openedAt)
        if model.reconsider(HubContext.decide(inputs), elapsed: elapsed) || model.session?.hasPick == true {
            endLateDecision()
        }
    }

    /// Ends the late decision: its wait is cancelled and its observation dropped.
    private func endLateDecision() {
        lateDecisionTask?.cancel()
        lateDecisionTask = nil
        lateDecisionLoop = nil
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
                let layout = NotchHubGeometry.island(
                    display: Self.display(of: screen),
                    contentHeight: DesignTokens.Island.contentHeight,
                    width: DesignTokens.Island.baseWidth
                )
            else {
                continue
            }
            zones[screen.displayID] = Zone(frame: screen.frame, hoverZone: layout.hoverZone)
        }
        if let placement = livePlacement {
            zones[placement.screenID]?.liveZone = placement.layout.hoverZone
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
            let isInLiveZone = zone.liveZone?.contains(x: local.x, y: local.y) ?? false
            if isInHubZone || isInLiveZone {
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

    /// Brings the tab of the first module that accepts file drags to the front for this opening
    /// only: the pick is a file drag's, not the user's, and is never remembered (D-04).
    private func showDropTab() {
        guard let module = model.runtimes.first(where: { $0.acceptsFileDrags }),
              model.selectedID != module.moduleID
        else {
            return
        }
        model.selectTemporarily(module.moduleID)
    }

    // MARK: Live activities

    /// What the policy needs to know about the Mac when the hub or the live state would show: read
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

    /// Reads, in one place, what the live state depends on, so that the loop follows each of them.
    private func activityInputs() -> ActivityInputs {
        ActivityInputs(
            activities: model.activities,
            isFullscreenSpace: appState?.activeSpace.isFullscreen ?? false,
            isMenuBarHidden: appState?.menuBarManager.isMenuBarHiddenBySystem ?? false
        )
    }

    /// The display the live state shows on, or `nil` when it must not show: nothing is live, the
    /// policy lets the hub not open there (fullscreen, a hidden menu bar, presenting, an excluded
    /// display) or the display has no layout. While the hub is open that is the display it is open
    /// on, else the preferred one.
    private func liveScreen(for board: HubActivityBoard.Board) -> NSScreen? {
        guard
            board.compact != nil,
            let appState,
            let screen = isOpen ? NSScreen.screens.first(where: { $0.displayID == openScreenID }) : preferredScreen(),
            NotchHubPolicy.blockReason(policyEnvironment(of: screen, appState: appState), trigger: .compact) == nil,
            NotchHubGeometry.live(display: Self.display(of: screen)) != nil,
            NotchHubGeometry.seed(display: Self.display(of: screen)) != nil
        else {
            return nil
        }
        return screen
    }

    /// Works out the board and tells the island's phase whether something is live: the live state
    /// starts, moves, ends or only follows the board. Called when an activity changes, when a
    /// fullscreen space or the hidden menu bar changes, when a finished activity leaves, when the
    /// hub has closed and when a space or the displays change while the live state shows.
    ///
    /// The live state shows only while an activity is live, the hub is closed and the policy lets
    /// the hub open on the display. While the hub is open the answer is only recorded: the hub
    /// closes into the live state when something is live.
    private func activitiesDidChange() {
        guard isActive else {
            hideLive()
            return
        }
        let board = model.board(now: .now)
        armExpiry(at: board.nextExpiry)
        let screen = liveScreen(for: board)
        let before = phase.target
        let wasVisible = phase.isPanelVisible
        send(.liveChanged(screen != nil))
        switch (before, phase.target) {
        case (.closed, .live):
            if let screen {
                startLive(board: board, on: screen, wasVisible: wasVisible)
            }
        case (.live, .live):
            if let screen {
                updateLive(board: board, on: screen)
            }
        case (.live, .closed):
            endLive()
        default:
            break
        }
    }

    /// Creates what the island shows and how it moves, once, with the live shape's click.
    private func ensurePresentation() -> IslandPresentation {
        if let presentation {
            return presentation
        }
        let presentation = IslandPresentation()
        presentation.onLiveTap = { [weak self] in
            // The click is handled after the view's own action has returned, because opening
            // the hub changes the view.
            Task { @MainActor in
                self?.liveWasClicked()
            }
        }
        self.presentation = presentation
        return presentation
    }

    /// Widens the closed island, or the notch, to the live shape: the hub's own panel and view,
    /// from the notch's rectangle, or from where a closing had got to.
    private func startLive(board: HubActivityBoard.Board, on screen: NSScreen, wasVisible: Bool) {
        let display = Self.display(of: screen)
        guard let live = NotchHubGeometry.live(display: display), let seed = NotchHubGeometry.seed(display: display) else {
            // Not reachable: the screen was chosen because both exist. Never leave a phase that
            // nothing completes.
            islandAnimationFinished(phase.generation)
            return
        }
        let panel = panel ?? NotchHubPanel()
        self.panel = panel
        let presentation = ensurePresentation()
        let existing = wasVisible && panelScreenFrame == screen.frame ? panel.contentView as? IslandHostingView : nil
        restShape = live.shape
        openShape = nil
        panelScreenFrame = screen.frame
        panel.hasShadow = false
        panel.applyDarkAppearance()
        panel.acceptsKeyboard = false
        panel.onEscape = nil
        presentation.takesKeyboard = false
        if existing == nil {
            let transition = NotchHubGeometry.transitionFrame(
                from: seed,
                to: live.shape,
                displayWidth: Double(screen.frame.width)
            )
            presentation.show(seed: seed, canvas: transition)
            presentation.liveBoard = board
            panel.contentView = IslandHostingView(
                view: IslandView(presentation: presentation, model: model, host: self)
            )
            setPanelFrame(transition, on: screen.frame)
            panel.orderFrontRegardless()
            // Lay the notch's shape out first, without animation, so that the widening starts from it.
            panel.contentView?.layoutSubtreeIfNeeded()
        } else {
            presentation.liveBoard = board
        }
        presentation.animateLive(
            to: live,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            generation: phase.generation
        ) { [weak self] generation in
            self?.islandAnimationFinished(generation)
        }
        setLivePlacement(LivePlacement(screenID: screen.displayID, layout: live))
    }

    /// Follows the board while the live state shows, and moves the shape at once when the display
    /// or its menu bar changed.
    private func updateLive(board: HubActivityBoard.Board, on screen: NSScreen) {
        guard let presentation, let live = NotchHubGeometry.live(display: Self.display(of: screen)) else {
            return
        }
        presentation.liveBoard = board
        if let placement = livePlacement, placement.screenID == screen.displayID, placement.layout == live {
            return
        }
        restShape = live.shape
        panelScreenFrame = screen.frame
        presentation.placeLive(live, canvas: live.shape)
        setPanelFrame(live.shape, on: screen.frame)
        setLivePlacement(LivePlacement(screenID: screen.displayID, layout: live))
    }

    /// Nothing is live any more: the shape returns into the notch and the panel goes when it has
    /// settled.
    private func endLive() {
        let screen = livePlacement.flatMap { placement in
            NSScreen.screens.first { $0.displayID == placement.screenID }
        }
        setLivePlacement(nil)
        animateClosing(on: screen)
    }

    /// Takes the live state away and ends what exists only while it shows. It leaves the panel
    /// alone: the island's phase orders it out when the shape has settled closed.
    private func hideLive() {
        setLivePlacement(nil)
    }

    /// Sets where the live state is, or `nil`. The live shape's rectangle is a place the pointer
    /// can rest to open the hub; the two tasks that follow space and display changes exist only
    /// while it is set.
    private func setLivePlacement(_ placement: LivePlacement?) {
        livePlacement = placement
        for id in zones.keys {
            zones[id]?.liveZone = nil
        }
        guard let placement else {
            for task in liveTasks {
                task.cancel()
            }
            liveTasks.removeAll()
            return
        }
        zones[placement.screenID]?.liveZone = placement.layout.hoverZone
        if liveTasks.isEmpty {
            startLiveObservers()
        }
    }

    /// The active space changed: works out the live state again and brings the panel along. The
    /// panel moves to the active space only when it is ordered to the front (`.moveToActiveSpace`),
    /// and the placement usually stays the same, so `updateLive` would not do it.
    private func activeSpaceDidChange() {
        activitiesDidChange()
        if livePlacement != nil, !isOpen {
            panel?.orderFrontRegardless()
        }
    }

    /// Follows the active space and the displays, only while the live state shows: on either it
    /// works out again where, and whether, the live state shows.
    private func startLiveObservers() {
        liveTasks = [
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                    self?.activeSpaceDidChange()
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

    /// Opens the hub on the live shape's display.
    private func liveWasClicked() {
        guard let screenID = livePlacement?.screenID else {
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
        appState.navigationState.openModuleSettings(moduleID)
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }

    var liveActivities: [LiveActivity] {
        model.activities
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
