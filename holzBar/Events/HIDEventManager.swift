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
            }
        }
    }

    /// The input monitors that are running.
    @ObservationIgnored private var runningKinds = Set<InputMonitors.Kind>()

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
        switch event.type {
        case .leftMouseDown:
            handleShowOnClick(appState: appState, screen: screen, clickTime: clickTime)
            handleSmartRehide(with: event, appState: appState, screen: screen)
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
            hasCustomAppearance: appState.appearanceManager.needsOverlayPanels(for: appState.appearanceManager.configuration)
        )
    }

    /// Starts the monitors the current settings need and stops the others.
    ///
    /// Each monitor wakes holzBar for every event of its kind in the whole system; the
    /// HID mouse-moved tap, for one, woke it on every mouse move even with "Show on
    /// hover" off. So a monitor runs only while the manager is enabled and
    /// `InputMonitors.needed(for:)` contains its kind. The macOS 27 system item click
    /// tap is needed whenever the manager is enabled.
    private func updateMonitors() {
        var wanted = Set<InputMonitors.Kind>()
        if isEnabled, let appState {
            wanted = InputMonitors.needed(for: inputMonitorSettings(appState: appState))
        }
        for kind in InputMonitors.Kind.allCases {
            let isRunning = runningKinds.contains(kind)
            if wanted.contains(kind), !isRunning {
                monitor(for: kind).start()
                runningKinds.insert(kind)
            } else if !wanted.contains(kind), isRunning {
                monitor(for: kind).stop()
                runningKinds.remove(kind)
            }
        }
        // Without the drag monitors a drag can never end, so it is not going on.
        if !runningKinds.contains(.mouseUp), isDraggingMenuBarItem {
            isDraggingMenuBarItem = false
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
            guard !targetSection.isHidden || appState.menuBarManager.zenMode.allows(.clickOnEmptyBar) else {
                logger.debug("Show on click: ignored in Zen mode")
                return
            }

            // On macOS 27 this also applies the concealment (`Concealer27.update()`).
            targetSection.toggle()
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

            // Get the window that was clicked.
            guard
                let mouseLocation = MouseHelpers.locationCoreGraphics,
                let windowUnderMouse = WindowInfo.createWindows(option: .onScreen)
                    .filter({ $0.layer < CGWindowLevelForKey(.cursorWindow) })
                    .first(where: { $0.bounds.contains(mouseLocation) && $0.title?.isEmpty == false }),
                let owningApplication = windowUnderMouse.owningApplication
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

        if appState.settings.advanced.showAllSectionsOnUserDrag {
            for section in appState.menuBarManager.sections {
                section.controlItem.state = .showSection
            }
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
        // `showOnHoverAllowed` is deliberately *not* checked here. It is cleared
        // when the user clicks in the menu bar, so that hovering does not
        // immediately undo a deliberate click, and it is restored only inside
        // `MenuBarSection.hide()`. Checking it here disabled the hide-on-leave
        // branch below as well — and that branch is what calls `hide()`. The flag
        // therefore latched off the only mechanism that could clear it, leaving
        // the holzBar Shelf on screen indefinitely: on whatever display it was opened
        // on, while the user worked on another one. It is checked in the reveal
        // branch instead, where it belongs.
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
                appState.menuBarManager.zenMode.allows(.hover),
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
                hiddenSection.show()
            }
        } else {
            guard
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
                // Make sure the mouse is still outside.
                guard
                    !isMouseInsideMenuBar(appState: appState, screen: screen),
                    !isMouseInsideShelf(appState: appState)
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
            guard appState.menuBarManager.zenMode.allows(.scroll) else {
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
