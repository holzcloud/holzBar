//
//  ItemReorderer27.swift
//  holzBar
//

import AppKit
import OSLog

/// Moves menu bar items on macOS 27 with a synthetic ⌘-drag.
///
/// MenuBarAgent lets the user move an item by dragging it with ⌘ held. holzBar posts the same
/// events at the item's Accessibility frame: the pointer moves onto the item, the left button
/// goes down with ⌘, thirty dragged events carry the pointer to just past a neighbour, and the
/// button goes up. These are the events `Scripts/macos27/reorder-probe.swift` posts. They use
/// public CGEvent and Accessibility calls only.
///
/// A drag is planned from a fresh read of the bar (``ReorderDrag``) and checked from another
/// one 1.2 s later. The button is always released, the pointer put back and the cursor shown
/// again, whatever happens, and nothing waits on the main thread: every wait is a
/// `Task.sleep`, and the Accessibility reads are the provider's own, off the main thread.
@available(macOS 27.0, *)
@MainActor
enum ItemReorderer27 {
    private static let logger = Logger(category: "ItemReorderer27")

    /// How long the bar needs after a drag to settle before it is read again (measured).
    private static let settleDelay = Duration.milliseconds(1200)
    /// The dragged events between press and release.
    private static let dragSteps = 30

    typealias EventError = MenuBarItemManager.EventError

    /// The bar as one read of the provider shows it.
    private struct Bar {
        /// Every item on screen, left to right.
        var items: [ReorderDrag.Item]
        /// The items that may be dragged: application items that macOS lets move.
        var movable: Set<String>
    }

    /// Puts one item before or after another one.
    ///
    /// - Throws: ``EventError/itemNotMovable(_:)`` for an item that cannot be dragged,
    ///   ``EventError/userInputNotPaused`` while the user keeps using the mouse, and
    ///   ``EventError/cannotComplete`` when the drag did not land.
    static func move(
        _ item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        appState: AppState
    ) async throws {
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let bar = await readBar() else {
            throw EventError.cannotComplete
        }
        let key = String(item.windowID)
        let target = String(destination.targetItem.windowID)
        guard bar.movable.contains(key), bar.movable.contains(target), key != target else {
            throw EventError.itemNotMovable(item)
        }
        let others = bar.items.map(\.id).filter { bar.movable.contains($0) && $0 != key }
        guard let targetIndex = others.firstIndex(of: target) else {
            throw EventError.cannotComplete
        }
        let before: String?
        switch destination {
        case .leftOfItem:
            before = target
        case .rightOfItem:
            before = targetIndex + 1 < others.count ? others[targetIndex + 1] : nil
        }
        let move = ReorderPlan.Move(key: key, before: before)
        if ReorderDrag.isPlaced(move, in: bar.items, sectionIDs: bar.movable) {
            return
        }
        guard let step = ReorderDrag.step(for: move, in: bar.items, sectionIDs: bar.movable, bias: .primary) else {
            throw EventError.cannotComplete
        }
        try await postDrag(step, appState: appState)
        do {
            try await Task.sleep(for: settleDelay)
        } catch {
            throw EventError.cannotComplete
        }
        guard
            let fresh = await readBar(),
            ReorderDrag.isPlaced(move, in: fresh.items, sectionIDs: fresh.movable)
        else {
            logger.notice("A command-drag did not land")
            throw EventError.cannotComplete
        }
    }

    // MARK: Reading the bar

    /// The items on screen, left to right, from a fresh Accessibility read. `nil` when the bar
    /// has no items.
    private static func readBar() async -> Bar? {
        let items = await MenuBarItemProvider27.items().filter(\.isOnScreen)
        guard !items.isEmpty else {
            return nil
        }
        let plain = items.map { item in
            ReorderDrag.Item(
                id: String(item.windowID),
                minX: Double(item.bounds.minX),
                maxX: Double(item.bounds.maxX),
                midY: Double(item.bounds.midY)
            )
        }
        let movable = Set(items.filter(isDraggable).map { String($0.windowID) })
        return Bar(items: plain, movable: movable)
    }

    /// Whether an item may be dragged: an application's item, not holzBar's control items and
    /// not a numbered system item of MenuBarAgent, which macOS pins.
    private static func isDraggable(_ item: MenuBarItem) -> Bool {
        item.isMovable && !item.isControlItem && item.tag.namespace != .menuBarAgent
    }

    // MARK: Posting

    /// Posts one ⌘-drag: pointer onto the item, press, thirty dragged events, release.
    ///
    /// holzBar's own event monitors are paused for the drag and the events carry the marker
    /// they ignore. The button is released, the pointer put back and the cursor shown again on
    /// every exit, also when the task is cancelled in the middle of the drag.
    private static func postDrag(_ step: ReorderDrag.Step, appState: AppState) async throws {
        try await MenuBarItemEventPoster.waitForUserToPauseInput()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }
        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }
        let original = CGEvent(source: nil)?.location
        defer {
            if let original {
                MouseHelpers.warpCursor(to: original)
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let from = CGPoint(x: step.from.x, y: step.from.y)
        let to = CGPoint(x: step.to.x, y: step.to.y)
        var releasePoint = from
        var buttonIsDown = false
        defer {
            if buttonIsDown {
                // The release is synchronous, so a cancelled drag never leaves the button down.
                post(.leftMouseUp, at: releasePoint, source: source)
            }
        }

        post(.mouseMoved, at: from, source: source)
        try await Task.sleep(for: .milliseconds(200))
        post(.leftMouseDown, at: from, source: source)
        buttonIsDown = true
        try await Task.sleep(for: .milliseconds(300))
        for number in 1...dragSteps {
            let fraction = Double(number) / Double(dragSteps)
            releasePoint = CGPoint(x: from.x + (to.x - from.x) * fraction, y: from.y)
            post(.leftMouseDragged, at: releasePoint, source: source)
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(300))
        releasePoint = to
        post(.leftMouseUp, at: to, source: source)
        buttonIsDown = false
    }

    /// Posts one mouse event with ⌘ held, marked so that holzBar's own handlers ignore it.
    private static func post(_ type: CGEventType, at point: CGPoint, source: CGEventSource?) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventSourceUserData, value: HIDEventManager.menuBarActivationMarker)
        event.post(tap: .cghidEventTap)
    }
}
