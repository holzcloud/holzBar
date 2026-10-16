//
//  MenuBarDragController.swift
//  holzBar
//

import Cocoa
import OSLog

/// The Drag in the Menu Bar module: a plain drag of an app's menu bar item moves it, as a
/// ⌘ Command-drag does.
///
/// The tap exists only between `start()` and `stop()`, which `HIDEventManager` calls with its other
/// monitors while the module is on. It listens to the three left-button event types and nothing
/// else. Its callback reads only what holzBar already holds in memory (the item cache, the
/// screens, the active Space), never Accessibility or the window list.
///
/// A press on an app's item is held back. A sideways move inside the bar replays the press as
/// a ⌘ Command-drag that macOS performs; a move down out of the bar replays a plain press into the
/// item's menu; a release replays a plain click. Every drop then sends the same intent as a move
/// in the Layout pane (`LayoutBarMoves`).
@MainActor
final class MenuBarDragController {
    /// The module's identifier, as stored with the user's choices.
    static let moduleID = "menu-bar-drag"

    /// Whether the running macOS supports the module: macOS 26 and later.
    static var isSupported: Bool {
        MenuBarBackendKind.current != .windowList
    }

    /// Marks the events holzBar replays, so the tap lets them through.
    static let replayMarker: Int64 = 0x1CE_77_DA6

    /// How long after the release the drop is handled, so macOS has placed the item.
    static let dropSettleDelay = Duration.milliseconds(500)

    /// No menu bar is taller; a press below this strip is let through without any lookup.
    private static let barStripHeight: CGFloat = 64

    /// A press on an app's item that is held back, and the bar as it was then.
    private struct Gesture {
        let dragged: MenuBarItem
        let draggedID: UInt32
        let pressBar: MenuBarDrop.Bar
        let pressFlags: CGEventFlags
        let currentSection: MenuBarDrop.Section?
        let displayID: CGDirectDisplayID
    }

    private weak var appState: AppState?
    private var tap: EventTap?
    private var decider = MenuBarDragDecider()
    private var gesture: Gesture?

    /// Whether a drop is being handled; presses pass unchanged until it is done, so the next hit
    /// test reads the bar as the drop left it.
    private var isHandlingDrop = false

    /// The longest callback of this run, written to the log when the tap stops.
    private var longestCallback = Duration.zero

    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private let logger = Logger(category: "MenuBarDrag")
    private let generation: MenuBarDrop.Generation

    /// - Parameter appState: The app state, which `HIDEventManager` holds weakly; without one the
    ///   controller lets every event through.
    init(appState: AppState?) {
        self.appState = appState
        self.generation = MenuBarBackendKind.current == .accessibility27 ? .macOS27 : .before27
    }

    // MARK: - Start and stop

    /// Creates the tap and enables it.
    func start() {
        if let tap {
            tap.enable()
            return
        }
        let tap = EventTap(
            label: "MenuBarDrag",
            types: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            location: .hidEventTap,
            placement: .headInsertEventTap,
            option: .defaultTap
        ) { [weak self] _, event in
            guard let self else {
                return event
            }
            return handle(event)
        }
        self.tap = tap
        tap.enable()
    }

    /// Releases the tap. A press held at that moment is dropped and its release then passes on its
    /// own; a drop being handled finishes, because holzBar's own move stops and restarts the
    /// monitors in its middle.
    func stop() {
        tap?.disable()
        tap = nil
        decider.reset()
        gesture = nil
        let longest = Self.microseconds(of: longestCallback)
        logger.debug("The longest tap callback of this run took \(longest, privacy: .public) µs")
        longestCallback = .zero
    }

    /// Creates the tap's port again if it is missing or invalid.
    ///
    /// - Returns: Whether the tap needed repair.
    func repair() -> Bool {
        guard let tap else {
            return false
        }
        let wasHealthy = tap.isValid && tap.isEnabled
        tap.enable()
        return !wasHealthy
    }

    // MARK: - The callback

    /// Handles an event of the tap; returns `nil` for an event that is held back.
    private func handle(_ event: CGEvent) -> CGEvent? {
        let start = ContinuousClock.now
        defer {
            noteDuration(of: start)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else {
            return event
        }
        switch event.type {
        case .leftMouseDown:
            return handleDown(event)
        case .leftMouseDragged:
            return handleDragged(event)
        case .leftMouseUp:
            return handleUp(event)
        default:
            return event
        }
    }

    /// Keeps the longest callback of the run and logs one that takes more than a millisecond.
    private func noteDuration(of start: ContinuousClock.Instant) {
        let duration = ContinuousClock.now - start
        longestCallback = max(longestCallback, duration)
        if duration > .milliseconds(1) {
            logger.debug("A tap callback took \(Self.microseconds(of: duration), privacy: .public) µs")
        }
    }

    private static func microseconds(of duration: Duration) -> Int64 {
        let parts = duration.components
        return parts.seconds * 1_000_000 + parts.attoseconds / 1_000_000_000_000
    }

    private func handleDown(_ event: CGEvent) -> CGEvent? {
        decider.reset()
        gesture = nil
        let location = event.location
        guard
            let appState,
            let displayID = Self.displayID(at: location),
            location.y - CGDisplayBounds(displayID).minY <= Self.barStripHeight,
            let bar = pressBar(on: displayID)
        else {
            return event
        }
        let hit = bar.item(at: location)
        let flags = event.flags
        let press = MenuBarDragPress(
            isOnAppItem: hit?.kind == .app,
            isBarShown: !appState.activeSpace.isFullscreen && !appState.menuBarManager.isMenuBarHiddenBySystem,
            isHandlingDrop: isHandlingDrop,
            isPostedByHolzBar: Self.isPostedByHolzBar(event),
            hasCommand: flags.contains(.maskCommand),
            hasControl: flags.contains(.maskControl),
            hasOption: flags.contains(.maskAlternate),
            clickCount: Int(event.getIntegerValueField(.mouseEventClickState))
        )
        guard
            press.isHeld,
            let hit,
            let item = appState.itemManager.itemCache.managedItems.first(where: { $0.windowID == hit.id })
        else {
            return event
        }
        _ = decider.mouseDown(at: location, time: ProcessInfo.processInfo.systemUptime, onItem: true)
        gesture = Gesture(
            dragged: item,
            draggedID: hit.id,
            pressBar: bar,
            pressFlags: flags,
            currentSection: appState.itemManager.itemCache.address(for: item.tag).map { Self.section($0.section) },
            displayID: displayID
        )
        return nil
    }

    /// Whether holzBar posted the event: from its own process, or the click that makes a display's
    /// menu bar active.
    private static func isPostedByHolzBar(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier)
            || event.getIntegerValueField(.eventSourceUserData) == HIDEventManager.menuBarActivationMarker
    }

    private func handleDragged(_ event: CGEvent) -> CGEvent? {
        guard let gesture else {
            return event
        }
        let location = event.location
        let action = decider.mouseDragged(
            to: location,
            time: ProcessInfo.processInfo.systemUptime,
            barMaxY: gesture.pressBar.barMaxY
        )
        switch action {
        case .pass, .replayClick:
            return event
        case .swallow:
            return nil
        case .rewriteWithCommand:
            addCommandInsideBar(event, bar: gesture.pressBar)
            return event
        case .replayCommandDown(let down):
            let flags = gesture.pressFlags.union(.maskCommand)
            post(.leftMouseDown, at: down, flags: flags)
            post(.leftMouseDragged, at: insideBar(location, bar: gesture.pressBar), flags: flags)
            return nil
        case .replayPlainDown(let down):
            post(.leftMouseDown, at: down, flags: gesture.pressFlags)
            post(.leftMouseDragged, at: location, flags: event.flags)
            self.gesture = nil
            return nil
        }
    }

    private func handleUp(_ event: CGEvent) -> CGEvent? {
        guard let gesture else {
            return event
        }
        let location = event.location
        let action = decider.mouseUp(at: location, time: ProcessInfo.processInfo.systemUptime)
        self.gesture = nil
        switch action {
        case .replayClick(let down, let up):
            post(.leftMouseDown, at: down, flags: gesture.pressFlags)
            post(.leftMouseUp, at: up, flags: gesture.pressFlags)
            return nil
        case .rewriteWithCommand:
            addCommandInsideBar(event, bar: gesture.pressBar)
            handleDrop(gesture, release: event.location, at: ContinuousClock.now)
            return event
        default:
            return event
        }
    }

    /// Adds ⌘ Command to an event of a decided drag and keeps it inside the bar, so a drop never
    /// lands below it, where macOS removes an item.
    private func addCommandInsideBar(_ event: CGEvent, bar: MenuBarDrop.Bar) {
        event.flags.insert(.maskCommand)
        event.location = insideBar(event.location, bar: bar)
    }

    /// The point moved up into the bar, two points above its bottom edge at most.
    private func insideBar(_ point: CGPoint, bar: MenuBarDrop.Bar) -> CGPoint {
        CGPoint(x: point.x, y: min(point.y, bar.barMaxY - 2))
    }

    // MARK: - The drop

    /// Handles a drop once, after the item has settled: one sleep, no loop.
    private func handleDrop(_ gesture: Gesture, release: CGPoint, at instant: ContinuousClock.Instant) {
        isHandlingDrop = true
        Task { [weak self] in
            await self?.finishDrop(gesture, release: release, settleAt: instant + Self.dropSettleDelay)
        }
    }

    private func finishDrop(_ gesture: Gesture, release: CGPoint, settleAt: ContinuousClock.Instant) async {
        defer {
            isHandlingDrop = false
        }
        try? await Task.sleep(until: settleAt, clock: .continuous)
        guard let appState else {
            return
        }
        // Before macOS 27 macOS has moved the item, so the intent is where it was placed. On
        // macOS 27 items move aside while dragging, so the release point is resolved against the
        // bar as it was at the press.
        var settledItems = [MenuBarItem]()
        var bar = gesture.pressBar
        let target: MenuBarDrop.Target?
        switch generation {
        case .before27:
            settledItems = await MenuBarItem.getMenuBarItems(on: gesture.displayID, option: .activeSpace)
            guard let settled = Self.bar(from: settledItems, on: gesture.displayID, generation: generation) else {
                return
            }
            bar = settled
            target = MenuBarDrop.placement(of: gesture.draggedID, in: settled)
        case .macOS27:
            target = MenuBarDrop.target(forDropAt: release, draggedID: gesture.draggedID, in: gesture.pressBar)
        }
        let intent = MenuBarDrop.intent(
            for: target,
            dragged: Self.dropItem(for: gesture.dragged),
            in: bar,
            currentSection: gesture.currentSection
        )
        await perform(intent, gesture: gesture, settledItems: settledItems, appState: appState)
        // The next hit test reads the bar as the drop left it.
        await appState.itemManager.cacheItemsRegardless()
    }

    private func perform(
        _ intent: MenuBarDrop.Intent,
        gesture: Gesture,
        settledItems: [MenuBarItem],
        appState: AppState
    ) async {
        switch intent {
        case .move(_, let target):
            let neighbourID: UInt32
            switch target {
            case .leftOf(let id), .rightOf(let id):
                neighbourID = id
            case .section:
                return
            }
            guard
                let dragged = settledItems.first(where: { $0.windowID == gesture.draggedID }),
                let neighbour = settledItems.first(where: { $0.windowID == neighbourID })
            else {
                logger.debug("A dropped item or its neighbour is gone")
                return
            }
            // A timeout skips the call, so the Layout pane's error alert never appears for a
            // drop made on the bar; macOS's own move stands.
            do {
                try await MenuBarItemEventPoster.waitForUserToPauseInput()
            } catch {
                logger.debug("The pointer kept moving after a drop")
                return
            }
            let destination: MenuBarItemManager.MoveDestination
            if case .leftOf = target {
                destination = .leftOfItem(neighbour)
            } else {
                destination = .rightOfItem(neighbour)
            }
            LayoutBarMoves.move(
                dragged,
                to: destination,
                appState: appState,
                actionName: String(localized: "Move \(dragged.displayName)")
            )
        case .setSection(_, let section):
            LayoutBarMoves.setSection(of: gesture.dragged, to: Self.name(of: section), appState: appState)
        case .macOSOrders:
            logger.debug("macOS ordered a dropped item")
        case .refused(let refusal):
            logger.debug("A drop was not acted on: \(String(describing: refusal), privacy: .public)")
        }
    }

    // MARK: - Reading the bar

    /// Posts a marked left-button event, so the tap lets it through and the replay is told apart
    /// from the user's own events.
    private func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return
        }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        if type != .leftMouseDragged {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }

    /// The bar of a display as the item cache holds it.
    private func pressBar(on displayID: CGDirectDisplayID) -> MenuBarDrop.Bar? {
        guard let appState else {
            return nil
        }
        return Self.bar(from: appState.itemManager.itemCache.managedItems, on: displayID, generation: generation)
    }

    /// The bar of a display made of the items whose centre lies on it, or `nil` without a screen
    /// of that display.
    private static func bar(
        from items: [MenuBarItem],
        on displayID: CGDirectDisplayID,
        generation: MenuBarDrop.Generation
    ) -> MenuBarDrop.Bar? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            return nil
        }
        let bounds = CGDisplayBounds(displayID)
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        let onDisplay = items.filter { bounds.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
        return MenuBarDrop.Bar(
            generation: generation,
            displayBounds: bounds,
            barMaxY: bounds.minY + height,
            items: onDisplay.map(dropItem(for:))
        )
    }

    private static func dropItem(for item: MenuBarItem) -> MenuBarDrop.Item {
        let kind: MenuBarDrop.Item.Kind
        if item.tag == .visibleControlItem {
            kind = .holzBarIcon
        } else if item.tag == .hiddenControlItem {
            kind = .hiddenDivider
        } else if item.tag == .alwaysHiddenControlItem {
            kind = .alwaysHiddenDivider
        } else if item.tag.namespace == .holzBar {
            kind = .holzBarOther
        } else if
            !item.isMovable || !item.canBeHidden || item.isSystemClone
                || item.tag.namespace.description.hasPrefix("com.apple.")
        {
            kind = .system
        } else {
            kind = .app
        }
        return MenuBarDrop.Item(id: item.windowID, kind: kind, frame: item.bounds)
    }

    /// The display under a point, in screen coordinates.
    private static func displayID(at point: CGPoint) -> CGDirectDisplayID? {
        var displayID = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count == 1 else {
            return nil
        }
        return displayID
    }

    private static func section(_ name: MenuBarSection.Name) -> MenuBarDrop.Section {
        switch name {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    private static func name(of section: MenuBarDrop.Section) -> MenuBarSection.Name {
        switch section {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }
}
