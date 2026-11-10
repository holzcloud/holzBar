//
//  HIDEventManager.swift
//  holzBar
//

import Cocoa
import Observation
import OSLog

/// Manager that monitors input events and implements the features
/// that are triggered by them, such as showing hidden items on
/// click/hover/scroll.
@MainActor
@Observable
final class HIDEventManager {
    /// A Boolean value that indicates whether the user is dragging
    /// a menu bar item.
    private(set) var isDraggingMenuBarItem = false

    /// The sections a Command-drag showed ("Show all sections on drag"): those whose control
    /// item was hiding its section when the drag started. The drop hides them again or hands
    /// them to the rehide (``RevealOwnership/afterDrop(revealed:autoRehide:collapsesAtDrop:)``).
    @ObservationIgnored private var dragRevealedSections = Set<MenuBarSection.Name>()

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

    /// Observers of the settings and state the monitors depend on.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// The task that re-evaluates the monitors when the screens change.
    @ObservationIgnored private var screenParametersTask: Task<Void, Never>?

    /// History of the manager's enabled states.
    @ObservationIgnored private var enabledStateStack = [Bool]()

    /// The windows above the menu bar's level from the last read, reused for a moment so
    /// mouse moves do not read the window list each (see `MenuBarHitTesting.swift`).
    @ObservationIgnored var windowsAboveMenuBar: (readAt: TimeInterval, windows: [MenuBarOcclusion.Window])?

    /// What the last menu bar hit test before macOS 27 took the bar's state from
    /// (``MenuBarAnchor``), for Copy Diagnostics. Set by the hit test only (see
    /// `MenuBarHitTesting.swift`); it runs on pointer moves, so no observer is woken.
    @ObservationIgnored var lastMenuBarAnchor: MenuBarAnchor.Kind = .icon

    /// The last empty menu bar spot hovered on each display (see `ItemClicker27`).
    @ObservationIgnored private var lastEmptyMenuBarPoints = [CGDirectDisplayID: CGPoint]()

    /// What show on hover does once its delay has passed.
    private enum HoverAction {
        case show
        case hide
    }

    /// The hover action waiting for its delay, so mouse moves start one task, not one each.
    @ObservationIgnored private var hoverSchedule = HoverSchedule<HoverAction>()

    /// The task that performs the pending hover action after the delay.
    @ObservationIgnored private var hoverTask: Task<Void, Never>?

    /// A Boolean value that indicates whether the manager is enabled.
    @ObservationIgnored private var isEnabled = false {
        didSet {
            updateMonitors()
            if !isEnabled {
                cancelHoverAction()
                appState?.cancelCommandDrag()
            }
        }
    }

    /// The input monitors that are running.
    @ObservationIgnored private var runningKinds = Set<InputMonitors.Kind>()

    /// The settings the running monitors were last evaluated for, so a change of the ⌘ Command
    /// state or of the armed press re-decides without reading every setting again.
    @ObservationIgnored private var currentSettings: InputMonitors.Settings?

    /// Whether a Command-press is armed, as the monitors were last told.
    @ObservationIgnored private var commandDragIsArmed = false

    /// Whether the system item click bridge is running.
    @ObservationIgnored private var isSystemItemClickBridgeRunning = false

    /// Cancels the pending hover action.
    private func cancelHoverAction() {
        hoverTask?.cancel()
        hoverTask = nil
        hoverSchedule.cancel()
    }

    // MARK: Monitors

    /// Monitor for mouse down events.
    @ObservationIgnored private(set) lazy var mouseDownMonitor = EventMonitor.universal(
        for: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
        // When the click arrived, for the latency of show on click.
        let clickTime = ProcessInfo.processInfo.systemUptime
        guard let self, isEnabled, let appState, let screen = bestScreen(appState: appState) else {
            return event
        }
        // holzBar's own click that makes a display's menu bar active (see `ItemClicker27`).
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == HIDEventManager.menuBarActivationMarker {
            return event
        }
        if appState.usage.isEnabled, let location = MouseHelpers.locationCoreGraphics {
            appState.usage.recordMenuBarClick(atCoreGraphicsPoint: location)
        }
        switch event.type {
        case .leftMouseDown:
            handleShowOnClick(appState: appState, screen: screen, clickTime: clickTime)
            handleSmartRehide(with: event, appState: appState, screen: screen)
            // A Command-drag of an app's item across holzBar's icon sets its section (macOS 27).
            if event.modifierFlags.contains(.command), #available(macOS 27.0, *) {
                // The module's own replayed presses are not a Command-drag of the user's.
                let moduleIsBusy = runningKinds.contains(.menuBarDrag) && menuBarDragController.isBusyWithDrop
                appState.commandDragSection27.pressed(event, moduleIsBusy: moduleIsBusy)
                commandDragArmedStateMayHaveChanged()
            }
        case .rightMouseDown:
            handleSecondaryContextMenu(appState: appState, screen: screen)
        default:
            return event
        }
        handlePreventShowOnHover(with: event, appState: appState, screen: screen)
        return event
    }

    /// Monitor for mouse up events.
    @ObservationIgnored private(set) lazy var mouseUpMonitor = EventMonitor.universal(
        for: .leftMouseUp
    ) { [weak self] event in
        guard let self, isEnabled else {
            return event
        }
        handleMenuBarItemDragStop()
        handleArrangementEnd(with: event)
        appState?.commandDragReleased(event)
        commandDragArmedStateMayHaveChanged()
        return event
    }

    /// Monitor for modifier key changes, which runs only for a Command-drag. Its handler does
    /// nothing but turn the Command-drag's two mouse monitors on or off.
    @ObservationIgnored private(set) lazy var modifierFlagsMonitor = EventMonitor.universal(
        for: .flagsChanged
    ) { [weak self] event in
        self?.commandKeyMayHaveChanged(isHeld: event.modifierFlags.contains(.command))
        return event
    }

    /// Monitor for mouse dragged events.
    @ObservationIgnored private(set) lazy var mouseDraggedMonitor = EventMonitor.universal(
        for: .leftMouseDragged
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleMenuBarItemDragStart(with: event, appState: appState, screen: screen)
        }
        return event
    }

    /// Tap for mouse moved events.
    @ObservationIgnored private(set) lazy var mouseMovedTap = EventTap(
        type: .mouseMoved,
        location: .hidEventTap,
        placement: .tailAppendEventTap,
        option: .listenOnly
    ) { [weak self] _, event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleShowOnHover(appState: appState, screen: screen)
        }
        return event
    }

    /// Monitor for scroll wheel events.
    @ObservationIgnored private(set) lazy var scrollWheelMonitor = EventMonitor.universal(
        for: .scrollWheel
    ) { [weak self] event in
        if let self, isEnabled, let appState, let screen = bestScreen(appState: appState) {
            handleShowOnScroll(with: event, appState: appState, screen: screen)
        }
        return event
    }

    /// The tap of the Drag in the Menu Bar module. It is created when the module is first on and
    /// holds nothing until it is started.
    @ObservationIgnored private lazy var menuBarDragController = MenuBarDragController(appState: appState)

    /// Whether the Drag in the Menu Bar tap was stopped and is kept, disabled, for its next
    /// start. Checked instead of the controller, so a module that was never on never creates it.
    @ObservationIgnored private var keepsMenuBarDragTap = false

    /// Logger for the event manager.
    @ObservationIgnored private let logger = Logger(category: "HIDEventManager")

    /// The tap that lets clicks reach the system items while items are concealed, where
    /// the backend needs one (`SystemItemClickBridge27`). It runs while the manager is enabled.
    @ObservationIgnored private var systemItemClickBridge: (any SystemItemClickBridge)?

    // MARK: Running Monitors

    /// The monitor for the given kind of input event. Monitors are created on first use,
    /// so one no setting needs (such as the mouse-moved tap) is never created.
    private func monitor(for kind: InputMonitors.Kind) -> any EventMonitorProtocol {
        switch kind {
        case .mouseDown:
            return mouseDownMonitor
        case .mouseUp:
            return mouseUpMonitor
        case .mouseDragged:
            return mouseDraggedMonitor
        case .mouseMoved:
            return mouseMovedTap
        case .scrollWheel:
            return scrollWheelMonitor
        case .menuBarDrag:
            return menuBarDragController
        case .modifierFlags:
            return modifierFlagsMonitor
        }
    }

    /// The settings that decide which input monitors run.
    private func inputMonitorSettings(appState: AppState) -> InputMonitors.Settings {
        let general = appState.settings.general
        let advanced = appState.settings.advanced
        let rehidesSmartly = general.rehideStrategy == .smart
        // The Shelf counts only when it is used on every display: elsewhere a click
        // still has to pause show on hover.
        let usesShelfEverywhere = general.useShelf && NSScreen.screens.allSatisfy { general.shelfDisplays.includes($0) }
        return InputMonitors.Settings(
            showOnClick: general.showOnClick,
            showOnHover: general.showOnHover,
            showOnScroll: general.showOnScroll,
            autoRehide: general.autoRehide,
            rehidesSmartly: rehidesSmartly,
            secondaryContextMenu: advanced.enableSecondaryContextMenu,
            usesShelf: usesShelfEverywhere,
            showAllSectionsOnUserDrag: advanced.showAllSectionsOnUserDrag,
            savesUserArrangement: MenuBarBackends.current.canMoveItems,
            setsSectionOnCommandDrag: MenuBarBackendKind.current == .accessibility27 && general.commandDragSetsSection,
            // Read here, not from events: ⌘ may be held already when the switch turns on or holzBar starts.
            commandHeld: NSEvent.modifierFlags.contains(.command),
            commandDragArmed: commandDragIsArmed,
            hasCustomAppearance: appState.appearanceManager.needsOverlayPanels(for: appState.appearanceManager.configuration),
            dragsWithoutCommand: MenuBarDragController.isSupported && appState.modules.isEnabled(MenuBarDragController.moduleID),
            countsUsage: appState.usage.isEnabled
        )
    }

    /// The usage suggestions were turned on or off: the mouse-down monitor runs only for them.
    func usageSettingChanged() {
        updateMonitors()
    }

    /// Starts the monitors the current settings need and stops the others.
    ///
    /// Each monitor wakes holzBar for every event of its kind in the whole system; the
    /// HID mouse-moved tap, for one, woke it on every mouse move even with "Show on
    /// hover" off. So a monitor runs only while the manager is enabled and
    /// `InputMonitors.needed(for:)` contains its kind. The macOS 27 system item click
    /// tap is needed whenever the manager is enabled.
    private func updateMonitors() {
        var settings = InputMonitors.Settings()
        if isEnabled, let appState {
            settings = inputMonitorSettings(appState: appState)
        }
        apply(settings)
    }

    /// The ⌘ Command key went down or up. Does nothing but re-decide the monitors.
    private func commandKeyMayHaveChanged(isHeld: Bool) {
        guard var settings = currentSettings, settings.commandHeld != isHeld else {
            return
        }
        settings.commandHeld = isHeld
        apply(settings)
    }

    /// A press may have been armed or ended: the mouse monitors stay until it is handled.
    private func commandDragArmedStateMayHaveChanged() {
        let isArmed = appState?.commandDragIsArmed ?? false
        guard var settings = currentSettings, isArmed != commandDragIsArmed else {
            return
        }
        commandDragIsArmed = isArmed
        settings.commandDragArmed = isArmed
        apply(settings)
    }

    /// Starts the monitors the settings need and stops the others.
    private func apply(_ settings: InputMonitors.Settings) {
        currentSettings = settings
        let wanted = InputMonitors.needed(for: settings)
        let setsSectionOnCommandDrag = settings.setsSectionOnCommandDrag
        for kind in InputMonitors.Kind.allCases {
            let isRunning = runningKinds.contains(kind)
            if wanted.contains(kind), !isRunning {
                monitor(for: kind).start()
                runningKinds.insert(kind)
            } else if !wanted.contains(kind), isRunning {
                monitor(for: kind).stop()
                runningKinds.remove(kind)
                if kind == .menuBarDrag {
                    keepsMenuBarDragTap = true
                }
            }
        }
        // The Drag in the Menu Bar tap is only disabled while the manager is (`stopAll()`
        // around holzBar's own moves), so it is not created anew for every move, and freed
        // once it is not wanted while the manager runs: the module was switched off, also
        // while the manager was disabled, so off still means no cost (pre27-L5).
        if wanted.contains(.menuBarDrag) {
            keepsMenuBarDragTap = false
        } else if isEnabled, keepsMenuBarDragTap {
            menuBarDragController.release()
            keepsMenuBarDragTap = false
        }
        // A Command-drag does not go on while the monitors stop or its switch is off.
        if !setsSectionOnCommandDrag {
            appState?.cancelCommandDrag()
            commandDragIsArmed = false
            currentSettings?.commandDragArmed = false
        }
        // Without the drag monitors a drag can never end, so it is not going on, and what
        // it showed collapses: no section stays marked shown (D-14).
        if !runningKinds.contains(.mouseUp), isDraggingMenuBarItem {
            isDraggingMenuBarItem = false
            collapseDragReveal()
        }
        if let systemItemClickBridge {
            if isEnabled, !isSystemItemClickBridgeRunning {
                systemItemClickBridge.start()
                isSystemItemClickBridgeRunning = true
            } else if !isEnabled, isSystemItemClickBridgeRunning {
                systemItemClickBridge.stop()
                isSystemItemClickBridgeRunning = false
            }
        }
    }

    // MARK: Setup

    /// Sets up the manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        systemItemClickBridge = MenuBarBackends.current.makeSystemItemClickBridge(appState: appState)
        startAll()
        configureObservers()
    }

    /// Configures the internal observers for the manager.
    private func configureObservers() {
        guard let appState else {
            return
        }

        // Re-evaluate the monitors whenever a setting that decides them changes.
        observers.append(
            ObservationLoop.observe { [weak self] in
                self?.inputMonitorSettings(appState: appState)
            } onChange: { [weak self] _ in
                self?.updateMonitors()
            }
        )
        screenParametersTask = Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.updateMonitors()
            }
        }

        // A tap created before Accessibility was granted has no port; check the monitors
        // once the permission is there.
        let accessibility = appState.permissions.accessibility
        observers.append(
            ObservationLoop.observe { accessibility.hasPermission } onChange: { [weak self] hasPermission in
                if hasPermission {
                    self?.healthCheck()
                }
            }
        )

        if let hiddenSection = appState.menuBarManager.section(withName: .hidden) {
            // In fullscreen mode, the menu bar slides down from the top on hover. Observe the
            // frame of the hidden section's control item, which we know will always be in the
            // menu bar, and run the show-on-hover check when it changes.
            let controlItem = hiddenSection.controlItem
            observers.append(
                ObservationLoop.observe {
                    (controlItem.frame, appState.activeSpace.isFullscreen, appState.menuBarManager.isMenuBarHiddenBySystem)
                } onChange: { [weak self, weak appState] values in
                    let (_, isFullscreen, isMenuBarHiddenBySystem) = values
                    guard let self, isEnabled, let appState, isFullscreen || isMenuBarHiddenBySystem else {
                        return
                    }
                    if let screen = bestScreen(appState: appState) {
                        handleShowOnHover(appState: appState, screen: screen)
                    }
                }
            )
        }
    }

    // MARK: Start/Stop

    /// Starts all monitors.
    func startAll() {
        isEnabled = enabledStateStack.popLast() ?? true
    }

    /// Stops all monitors.
    func stopAll() {
        enabledStateStack.append(isEnabled)
        isEnabled = false
    }

    // MARK: Health Check

    /// Repairs the running monitors: taps whose port is missing or invalid are created
    /// again, AppKit's monitors are installed anew and the system item click tap is
    /// restarted.
    ///
    /// Runs once the bar has settled after the screen was locked, the Mac slept, the
    /// session was away or the displays changed, and when Accessibility is granted.
    func healthCheck() {
        var repaired = [String]()
        for kind in InputMonitors.Kind.allCases where runningKinds.contains(kind) {
            if monitor(for: kind).repair() {
                repaired.append(String(describing: kind))
            }
        }
        if let systemItemClickBridge, isSystemItemClickBridgeRunning {
            systemItemClickBridge.stop()
            systemItemClickBridge.start()
            repaired.append("system item click tap")
        }
        logger.info("Health check: restarted \(repaired.joined(separator: ", "), privacy: .public)")
    }
}

// MARK: - Handler Methods

extension HIDEventManager {

    // MARK: Handle Show On Click

    /// Shows or hides a section after a click on empty menu bar space.
    ///
    /// Nothing here asks another application: the hit test reads the application menu
    /// from `ApplicationMenuFrames`, so the reveal follows the click at once.
    ///
    /// - Parameter clickTime: The system uptime when the click arrived.
    private func handleShowOnClick(appState: AppState, screen: NSScreen, clickTime: TimeInterval) {
        guard
            appState.settings.general.showOnClick,
            isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen)
        else {
            return
        }

        Task {
            if NSEvent.heldModifierFlags == .control {
                handleSecondaryContextMenu(appState: appState, screen: screen)
                return
            }

            let targetSection: MenuBarSection

            if
                NSEvent.heldModifierFlags == .option,
                let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                alwaysHiddenSection.isEnabled
            {
                targetSection = alwaysHiddenSection
            } else if
                let hiddenSection = appState.menuBarManager.section(withName: .hidden),
                hiddenSection.isEnabled
            {
                targetSection = hiddenSection
            } else {
                return
            }

            // Zen mode refuses to reveal; hiding what the user showed stays possible.
            guard !targetSection.isHidden || appState.menuBarManager.allowsReveal(.clickOnEmptyBar) else {
                logger.debug("Show on click: ignored in Zen mode")
                return
            }

            // On macOS 27 this also applies the concealment (`Concealer27.update()`).
            targetSection.toggle(origin: .click)
            let milliseconds = Int((ProcessInfo.processInfo.systemUptime - clickTime) * 1000)
            logger.debug("Show on click: revealed \(milliseconds, privacy: .public) ms after the click")
        }
    }

    // MARK: Handle Smart Rehide

    private func handleSmartRehide(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.autoRehide,
            case .smart = appState.settings.general.rehideStrategy
        else {
            return
        }

        // Make sure clicking the holzBar icon doesn't trigger rehide.
        if let holzBarIcon = appState.menuBarManager.controlItem(withName: .visible) {
            guard event.window !== holzBarIcon.window else {
                return
            }
        }

        // Only continue if the click is not inside the holzBar Shelf, at
        // least one section is visible, and the mouse is not inside
        // the menu bar.
        guard
            event.window !== appState.menuBarManager.shelfPanel,
            appState.menuBarManager.hasVisibleSection,
            !isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        let initialSpaceID = Bridging.getActiveSpaceID()

        Task {
            // Give the window under the mouse a chance to focus.
            try? await Task.sleep(for: .milliseconds(250))

            // Don't bother checking the window if the click caused
            // a space change.
            if Bridging.getActiveSpaceID() != initialSpaceID {
                for section in appState.menuBarManager.sections {
                    section.hide()
                }
                return
            }

            // Get the window that was clicked: the topmost app window (layer 0) or Dock
            // window under the mouse (RehideClickTarget). Not by title: macOS withholds
            // other apps' window titles without Screen Recording, which smart rehide does
            // not need.
            let windows = WindowInfo.createWindows(option: .onScreen)
            let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            guard
                let mouseLocation = MouseHelpers.locationCoreGraphics,
                let index = RehideClickTarget.clickedWindowIndex(
                    in: windows.map { RehideClickTarget.Window(layer: $0.layer, ownerPID: $0.ownerPID, bounds: $0.bounds) },
                    at: mouseLocation,
                    cursorLayer: Int(CGWindowLevelForKey(.cursorWindow)),
                    dockPID: dockPID
                ),
                let owningApplication = windows[index].owningApplication
            else {
                return
            }

            // Note: The Dock is an exception to the following check.
            if owningApplication.bundleIdentifier != "com.apple.dock" {
                // Only continue if the clicked app is active, and has
                // a regular activation policy.
                guard
                    owningApplication.isActive,
                    owningApplication.activationPolicy == .regular
                else {
                    return
                }
            }

            // All checks have passed, hide the sections.
            for section in appState.menuBarManager.sections {
                section.hide()
            }
        }
    }

    // MARK: Handle Secondary Context Menu

    private func handleSecondaryContextMenu(appState: AppState, screen: NSScreen) {
        Task {
            guard
                appState.settings.advanced.enableSecondaryContextMenu,
                isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen),
                let mouseLocation = MouseHelpers.locationAppKit
            else {
                return
            }
            // Delay prevents the menu from immediately closing.
            try? await Task.sleep(for: .milliseconds(100))
            appState.menuBarManager.showSecondaryContextMenu(at: mouseLocation)
        }
    }

    // MARK: Handle Menu Bar Item Drag Stop

    private func handleMenuBarItemDragStop() {
        if isDraggingMenuBarItem {
            isDraggingMenuBarItem = false
            // The user arranged items on the bar: their sections are saved once the bar
            // shows the result (see `SectionRestore.swift`).
            appState?.itemManager.saveSectionsSoon()
            endDragReveal()
        }
    }

    // MARK: Handle Command-Drag Reveal

    /// What a Command-drag showed, after the drop: on macOS 27, in the Shelf and with automatic
    /// rehide off it collapses at once; otherwise the rehide strategy hides it, as any show
    /// (D-07, D-13, D-14).
    private func endDragReveal() {
        guard let appState, !dragRevealedSections.isEmpty else {
            dragRevealedSections = []
            return
        }
        let general = appState.settings.general
        let revealed = Set(dragRevealedSections.map(\.ownershipSection))
        // The Shelf never shows the sections in the bar, so what the drag expanded there
        // collapses at the drop as well.
        let action = RevealOwnership.afterDrop(
            revealed: revealed,
            autoRehide: general.autoRehide,
            collapsesAtDrop: MenuBarBackendKind.current == .accessibility27 || general.usesShelf
        )
        switch action {
        case .nothing:
            dragRevealedSections = []
        case .collapse:
            collapseDragReveal()
        case .rehide(let sections):
            let manager = appState.menuBarManager
            dragRevealedSections = []
            manager.revealOwnership.didShow(.drag, expanded: sections)
            // The deepest section the drag showed collapses every section it expanded
            // (`RevealOwnership.sectionsToHide(rehiding:)`).
            let deepest = [MenuBarSection.Name.alwaysHidden, .hidden]
                .filter { sections.contains($0.ownershipSection) }
                .compactMap { manager.section(withName: $0) }
                .first { $0.isEnabled }
            deepest?.armRehide()
        }
    }

    /// Hides exactly the sections the Command-drag showed, and on macOS 27 lets the concealer
    /// follow once, so even a reveal another update made visible during the drag ends (D-14).
    private func collapseDragReveal() {
        let names = dragRevealedSections
        dragRevealedSections = []
        guard let appState, !names.isEmpty else {
            return
        }
        for section in appState.menuBarManager.sections where names.contains(section.name) {
            section.controlItem.state = .hideSection
        }
        if #available(macOS 27.0, *) {
            appState.concealer27.update()
        }
    }

    // MARK: Handle Arrangement End

    /// Notes the end of a Command-drag on the menu bar when the drag monitors do not run
    /// (they run only for "Show all sections on drag" or a custom appearance), so the
    /// sections the user arranged are saved before anything restores the old ones.
    private func handleArrangementEnd(with event: NSEvent) {
        guard
            !runningKinds.contains(.mouseDragged),
            event.modifierFlags.contains(.command),
            let appState,
            let screen = bestScreen(appState: appState),
            isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }
        appState.itemManager.saveSectionsSoon()
    }

    // MARK: Handle Menu Bar Item Drag Start

    private func handleMenuBarItemDragStart(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            !isDraggingMenuBarItem,
            event.modifierFlags.contains(.command),
            isMouseInsideMenuBar(appState: appState, screen: screen)
        else {
            return
        }

        isDraggingMenuBarItem = true

        // The drag shows every section only when nothing refuses a reveal now: the lock (no
        // Touch ID prompt in the middle of a drag), Zen mode, manual or while the screen is
        // shared, and a display set to Collapse. Otherwise it only arranges what is visible
        // (D-07, D-14).
        guard
            appState.settings.advanced.showAllSectionsOnUserDrag,
            !appState.hiddenItemsLock.requiresAuthentication,
            appState.menuBarManager.allowsReveal(.commandDrag)
        else {
            return
        }
        // The control item states, not `isHidden`, whose Shelf branch reads the panel: these
        // are the states this drag changes and the drop restores.
        let sections = appState.menuBarManager.sections
        dragRevealedSections = Set(sections.filter { $0.controlItem.state == .hideSection }.map(\.name))
        for section in sections {
            section.controlItem.state = .showSection
        }
    }

    // MARK: Menu Bar Activation

    /// Marks holzBar's click that makes a display's menu bar active before an item is pressed.
    static let menuBarActivationMarker: Int64 = 0x1CE_27_BA2

    /// The last empty menu bar spot hovered on the given display.
    func lastEmptyMenuBarPoint(for displayID: CGDirectDisplayID) -> CGPoint? {
        lastEmptyMenuBarPoints[displayID]
    }

    // MARK: Handle Show On Hover

    private func handleShowOnHover(appState: AppState, screen: NSScreen) {
        // Make sure the "ShowOnHover" feature is enabled.
        //
        // Hover hides only what hover showed (`RevealOwnership.hoverOwns`): a section
        // shown by a click, a hotkey, the holzBar icon, the Shelf or any other way stays
        // until the rehide strategy hides it, and a click on an item while hover owns the
        // reveal makes it the user's (`handlePreventShowOnHover`).
        //
        // `showOnHoverAllowed` is deliberately *not* checked here and never gates the
        // hide. It is cleared when the user clicks in the menu bar, so that hovering does
        // not immediately undo a deliberate click, and it is restored only inside
        // `MenuBarSection.hide()`. As the hide gate it latched off the only mechanism that
        // could clear it, leaving the holzBar Shelf on screen indefinitely: on whatever
        // display it was opened on, while the user worked on another one. It is checked in
        // the reveal branch instead, where it belongs; ownership decides the hide.
        guard appState.settings.general.showOnHover else {
            return
        }

        // Only continue if we have a hidden section (we should).
        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden) else {
            return
        }

        let delay = appState.settings.advanced.showOnHoverDelay

        if hiddenSection.isHidden {
            guard
                appState.menuBarManager.showOnHoverAllowed,
                appState.menuBarManager.allowsReveal(.hover),
                isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen)
            else {
                return
            }
            if let location = MouseHelpers.locationCoreGraphics {
                lastEmptyMenuBarPoints[screen.displayID] = location
            }
            // A show already waiting keeps its timing, counted from the first move.
            guard let generation = hoverSchedule.request(.show) else {
                return
            }
            hoverTask?.cancel()
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else {
                    return
                }
                hoverSchedule.finish(generation)
                // Make sure the mouse is still inside.
                guard isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) else {
                    return
                }
                hiddenSection.show(origin: .hover)
            }
        } else {
            guard
                appState.menuBarManager.revealOwnership.hoverOwns,
                !isMouseInsideMenuBar(appState: appState, screen: screen),
                !isMouseInsideShelf(appState: appState)
            else {
                return
            }
            // A hide already waiting keeps its timing, counted from the first move.
            guard let generation = hoverSchedule.request(.hide) else {
                return
            }
            hoverTask?.cancel()
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else {
                    return
                }
                hoverSchedule.finish(generation)
                // Make sure hover still owns the reveal and the mouse is still outside.
                guard
                    appState.menuBarManager.revealOwnership.hoverOwns,
                    !isMouseInsideMenuBar(appState: appState, screen: screen),
                    !isMouseInsideShelf(appState: appState),
                    // Never while a hidden item's menu is open; the next move asks again.
                    !hiddenSection.hasOpenItemMenu
                else {
                    return
                }
                hiddenSection.hide()
            }
        }
    }

    // MARK: Handle Prevent Show On Hover

    private func handlePreventShowOnHover(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.showOnHover,
            !appState.settings.general.usesShelf
        else {
            return
        }

        guard isMouseInsideMenuBar(appState: appState, screen: screen) else {
            return
        }

        if isMouseInsideMenuBarItem(appState: appState, screen: screen) {
            switch event.type {
            case .leftMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                if isMouseInsideHolzBarIcon(appState: appState) {
                    break
                }
                return
            case .rightMouseDown:
                if appState.menuBarManager.hasVisibleSection {
                    break
                }
                return
            default:
                return
            }
        } else if isMouseInsideApplicationMenu(appState: appState, screen: screen) {
            return
        }

        // Mouse is inside the menu bar, outside an item or application
        // menu, so it must be inside an empty menu bar space.
        appState.menuBarManager.showOnHoverAllowed = false
        // A click while hover owns the reveal makes it the user's: moving the pointer
        // away no longer hides it. A peek, a rule or a change reveal keeps its own hide.
        appState.menuBarManager.revealOwnership.takeOverFromHover(by: .click)
    }

    // MARK: Handle Show On Scroll

    private func handleShowOnScroll(with event: NSEvent, appState: AppState, screen: NSScreen) {
        guard
            appState.settings.general.showOnScroll,
            isMouseInsideMenuBar(appState: appState, screen: screen),
            let hiddenSection = appState.menuBarManager.section(withName: .hidden)
        else {
            return
        }

        let averageDelta: CGFloat
        if event.hasPreciseScrollingDeltas {
            averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) / 2
        } else {
            // A mouse wheel reports whole lines rather than points, so a single
            // notch has a delta of 1 and never reached the threshold below
            // (jordanbaird/Ice#717).
            averageDelta = (event.scrollingDeltaX + event.scrollingDeltaY) * 10
        }

        if averageDelta > 5 {
            guard appState.menuBarManager.allowsReveal(.scroll) else {
                return
            }
            hiddenSection.show()
        } else if averageDelta < -5 {
            hiddenSection.hide()
        }
    }
}

// MARK: - EventMonitor Helpers

/// Helper protocol to enable group operations across event
/// monitoring types.
@MainActor
private protocol EventMonitorProtocol {
    func start()
    func stop()

    /// Repairs the running monitor and returns whether it did anything.
    func repair() -> Bool
}

extension EventMonitor: EventMonitorProtocol {
    fileprivate func repair() -> Bool {
        restart()
        return true
    }
}

extension EventTap: EventMonitorProtocol {
    fileprivate func start() {
        enable()
    }

    fileprivate func stop() {
        disable()
    }

    fileprivate func repair() -> Bool {
        let wasHealthy = isValid && isEnabled
        enable()
        return !wasHealthy
    }
}

extension MenuBarDragController: EventMonitorProtocol {}
