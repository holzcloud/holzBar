//
//  CommandDragSection27.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// Sets an application's section from a Command-drag of its item across holzBar's icon on macOS 27.
///
/// macOS 27 reorders the bar by itself during a Command-drag and holzBar draws no dividers, so the
/// icon is the only boundary: an item dragged from its right to its left is hidden, one dragged
/// from its left to its right is visible (`CommandDragSection` decides). holzBar does not watch the
/// drag. The mouse-down monitor arms one press, the mouse-up monitor starts one settle task, which
/// waits for the bar to settle, reads it once through Accessibility (a second time at most when the
/// item or the icon was missing) and writes the section through `Concealer27.setSection`. There is
/// no timer, event tap or drag monitor, and the pointer is never moved.
@available(macOS 27.0, *)
@MainActor
@Observable
final class CommandDragSection27 {
    /// How long the bar needs after a Command-drag to settle before it is read (the value measured
    /// for `ItemReorderer27`; tuned from the diagnostics line in the beta test).
    static let settleDelay = Duration.milliseconds(1200)

    /// How long the one retry waits when the first read lacked the dragged item or the icon.
    static let retryDelay = Duration.milliseconds(600)

    /// The last Command-drag in fixed words (how long it waited, how many reads, the decision and
    /// what became of it), for Copy Diagnostics. Never a name or a position; empty before the
    /// first one.
    private(set) static var lastSummary = ""

    /// What the drops told the user, newest first. Kept in memory only: never stored, exported,
    /// synced or logged.
    private(set) var notices = [CommandDragNotice]()

    /// What a press is on, which decides how its release is treated.
    private enum Subject {
        /// An application's item that may be free; `lock` is a rule's. Decided from the settled bar.
        case item(draggedID: UInt32, lock: CommandDragSection.Lock?)
        /// An item macOS keeps in place, a pinned or numbered system one: its bar after the drop
        /// would show no crossing, so the pointer alone decides.
        case fixed(frame: CGRect, lock: CommandDragSection.Lock)
        /// A press that ends without a read, with the reason that is recorded.
        case skipped(CommandDragSection.Reason)
    }

    /// A press of the left button with Command held, in the menu bar.
    private struct Press {
        let subject: Subject
        /// The application's layout key; `nil` for a numbered system item or an item without one.
        let key: String?
        /// The application's name, for the notice.
        let name: String
        /// The bar as the item cache held it at the press; `nil` for a press on another display.
        let bar: MenuBarDrop.Bar?
        let point: CGPoint
        let displayID: CGDirectDisplayID
    }

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var armed: Press?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(category: "CommandDragSection27")

    init(appState: AppState?) {
        self.appState = appState
    }

    // MARK: - Press and release

    /// Arms a press when the event is a Command-press in the menu bar, from the user's own hand.
    ///
    /// - Parameter moduleIsBusy: Whether the Drag in the Menu Bar module is handling a drop, whose
    ///   replayed presses are never a Command-drag of the user's.
    func pressed(_ event: NSEvent, moduleIsBusy: Bool) {
        guard
            let appState,
            event.type == .leftMouseDown,
            MenuBarBackendKind.current == .accessibility27,
            appState.settings.general.commandDragSetsSection
        else {
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), flags.isDisjoint(with: [.control, .option]) else {
            return
        }
        // holzBar's own drags (sorting, the module's replays) are never recorded.
        guard !moduleIsBusy, !ItemReorderer27.isRunning, !Self.isPostedByHolzBar(event) else {
            return
        }
        guard
            !appState.activeSpace.isFullscreen,
            !appState.menuBarManager.isMenuBarHiddenBySystem,
            let activeDisplayID = Bridging.getActiveMenuBarDisplayID(),
            let point = event.cgEvent?.location ?? MouseHelpers.locationCoreGraphics
        else {
            return
        }
        guard let press = press(at: point, activeDisplayID: activeDisplayID, appState: appState) else {
            return
        }
        supersedeGesture()
        armed = press
    }

    /// What a press at a point is on, or `nil` when it is not on the menu bar's items.
    private func press(at point: CGPoint, activeDisplayID: CGDirectDisplayID, appState: AppState) -> Press? {
        guard CGDisplayBounds(activeDisplayID).contains(point) else {
            // The bar of another display is not the active one, whose items are not read.
            guard Self.isInBarStrip(point, excluding: activeDisplayID) else {
                return nil
            }
            return Press(subject: .skipped(.otherDisplay), key: nil, name: "", bar: nil, point: point, displayID: activeDisplayID)
        }
        let managed = appState.itemManager.itemCache.managedItems
        guard let bar = Self.bar(from: managed, on: activeDisplayID, concealed: appState.concealer27.concealedPIDs) else {
            return nil
        }
        guard let hit = bar.item(at: point) else {
            // A numbered system item is not in the cache; its frame is from the last read.
            guard
                bar.displayBounds.contains(point),
                point.y <= bar.barMaxY,
                let frame = MenuBarItemProvider27.systemItemFrames(for: activeDisplayID).first(where: { $0.contains(point) })
            else {
                return nil
            }
            return Press(subject: .fixed(frame: frame, lock: .system), key: nil, name: "", bar: bar, point: point, displayID: activeDisplayID)
        }
        guard let item = managed.first(where: { $0.windowID == hit.id }) else {
            return nil
        }
        let key = item.layoutKey27
        let name = item.sourceApplication?.localizedName ?? item.displayName
        func makePress(_ subject: Subject) -> Press {
            Press(subject: subject, key: key, name: name, bar: bar, point: point, displayID: activeDisplayID)
        }
        // holzBar's own items (the icon, the dividers, widgets) are never an application's.
        switch hit.kind {
        case .holzBarIcon, .hiddenDivider, .alwaysHiddenDivider, .holzBarOther:
            return makePress(.skipped(.notAnAppItem))
        case .app, .system:
            break
        }
        let identity = appState.itemManager.identityKey(for: item)
        if !item.isMovable || !item.canBeHidden || PinnedSystemItems.isPinned(key: identity) {
            return makePress(key == nil ? .skipped(.noKey) : .fixed(frame: hit.frame, lock: .pinned))
        }
        guard hit.kind == .app else {
            return makePress(.skipped(.notAnAppItem))
        }
        guard key != nil else {
            return makePress(.skipped(.noKey))
        }
        let manager = appState.itemManager
        let isControlledByRule = appState.automation.controlledItemKeys.map(manager.storedIdentityKey).contains(identity)
        return makePress(.item(draggedID: hit.id, lock: isControlledByRule ? .rule : nil))
    }

    /// Starts the settle task of the armed press; without one the release is not a Command-drag's.
    func released(_ event: NSEvent) {
        guard let press = armed else {
            return
        }
        armed = nil
        guard let release = event.cgEvent?.location ?? MouseHelpers.locationCoreGraphics else {
            return
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            await self?.settle(press, release: release)
        }
    }

    /// Forgets the armed press and stops the settle task, when the monitors stop.
    func cancel() {
        armed = nil
        settleTask?.cancel()
        settleTask = nil
    }

    /// A new press replaces a gesture still armed or settling.
    private func supersedeGesture() {
        guard armed != nil || settleTask != nil else {
            return
        }
        cancel()
        record(CommandDragSection.summary(
            waitedMilliseconds: 0,
            reads: 0,
            decision: .ignore(.superseded),
            outcome: .nothing
        ))
    }

    // MARK: - Settling

    /// Waits for the bar to settle, reads it, decides and applies.
    private func settle(_ press: Press, release: CGPoint) async {
        let started = ContinuousClock.now
        var settled: MenuBarDrop.Bar?
        var reads = 0
        // A click without movement decides at once, without a read; so does any press that has
        // nothing to read: only an application's item needs the bar after the drop.
        let isMoved = abs(release.x - press.point.x) >= CommandDragSection.movementThreshold
        if isMoved, case .item(let draggedID, _) = press.subject {
            guard await waitForBarToSettle() else {
                return
            }
            settled = await readBar(for: press)
            reads = 1
            if !Self.isComplete(settled, draggedID: draggedID) {
                do {
                    try await Task.sleep(for: Self.retryDelay)
                } catch {
                    return
                }
                settled = await readBar(for: press)
                reads = 2
            }
        }
        guard !Task.isCancelled, let appState else {
            return
        }
        let waited = Self.milliseconds(of: ContinuousClock.now - started)
        let (decision, lock) = decision(for: press, release: release, settled: settled, isMoved: isMoved)
        let current = press.key.map { Self.dropSection(appState.concealer27.section(forKey: $0)) } ?? .visible
        let outcome = CommandDragSection.outcome(for: decision, current: current, lock: lock)
        apply(outcome, decision: decision, current: current, press: press, appState: appState)
        record(CommandDragSection.summary(waitedMilliseconds: waited, reads: reads, decision: decision, outcome: outcome))
        settleTask = nil
    }

    /// What the release means, and the lock that keeps the application's section as it is.
    private func decision(
        for press: Press,
        release: CGPoint,
        settled: MenuBarDrop.Bar?,
        isMoved: Bool
    ) -> (CommandDragSection.Decision, CommandDragSection.Lock?) {
        guard isMoved else {
            return (.ignore(.noMovement), nil)
        }
        switch press.subject {
        case .skipped(let reason):
            return (.ignore(reason), nil)
        case .fixed(let frame, let lock):
            guard let bar = press.bar else {
                return (.ignore(.noIcon), nil)
            }
            let decision = CommandDragSection.decideFixed(draggedFrame: frame, press: bar, pressPoint: press.point, release: release)
            return (decision, lock)
        case .item(let draggedID, let lock):
            guard Bridging.getActiveMenuBarDisplayID() == press.displayID, let bar = press.bar else {
                return (.ignore(.otherDisplay), nil)
            }
            let decision = CommandDragSection.decide(
                draggedID: draggedID,
                press: bar,
                pressPoint: press.point,
                release: release,
                settled: settled
            )
            return (decision, lock)
        }
    }

    /// Waits for the sections' own changes and the bar's animation after the drop; `false` when
    /// the task was cancelled meanwhile.
    private func waitForBarToSettle() async -> Bool {
        do {
            try await Task.sleep(for: Self.settleDelay)
            guard let appState else {
                return false
            }
            await appState.concealer27.waitForPendingApplies()
            if let remaining = appState.concealer27.timeUntilSettled() {
                try await Task.sleep(for: remaining)
            }
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    /// The bar after the drop, from one Accessibility read; `nil` when it cannot be built.
    private func readBar(for press: Press) async -> MenuBarDrop.Bar? {
        let items = await MenuBarItemProvider27.items()
        guard !Task.isCancelled, let appState else {
            return nil
        }
        let managed = items.filter { $0.canBeHidden && !$0.isSystemClone }
        return Self.bar(from: managed, on: press.displayID, concealed: appState.concealer27.concealedPIDs)
    }

    /// Writes the section of an applied drop and tells the user; a kept item gets a notice and no write.
    private func apply(
        _ outcome: CommandDragSection.Outcome,
        decision: CommandDragSection.Decision,
        current: MenuBarDrop.Section,
        press: Press,
        appState: AppState
    ) {
        switch outcome {
        case .nothing:
            return
        case .apply(let from, let to):
            guard let key = press.key else {
                return
            }
            appState.concealer27.setSection(Self.macOS27Section(to), for: key)
            // A rule that controls the item has to look at it again.
            appState.automation.itemsWereArrangedByHand()
            add(CommandDragNotice.make(key: key, name: press.name, kind: .set(from: from, to: to)))
        case .keep(let lock):
            guard case .set(let target) = decision else {
                return
            }
            if lock == .system {
                // A numbered system item has no section and no name.
                add(.system())
            } else if let key = press.key, target != current {
                add(CommandDragNotice.make(key: key, name: press.name, kind: .kept(lock)))
            }
        }
    }

    private func add(_ notice: CommandDragNotice) {
        notices = CommandDragNotices.adding(notice, to: notices)
    }

    // MARK: - Notices

    /// Puts the application's former section back, if it still is the one the drop set; the
    /// notice goes either way.
    func undo(_ notice: CommandDragNotice) {
        dismiss(notice)
        guard case .set(let from, let to) = notice.kind, let appState else {
            return
        }
        guard appState.concealer27.section(forKey: notice.id) == Self.macOS27Section(to) else {
            return
        }
        appState.concealer27.setSection(Self.macOS27Section(from), for: notice.id)
        appState.automation.itemsWereArrangedByHand()
    }

    /// Removes a notice.
    func dismiss(_ notice: CommandDragNotice) {
        notices.removeAll { $0 == notice }
    }

    /// Keeps the summary for Copy Diagnostics and logs it: fixed words and numbers only.
    private func record(_ summary: String) {
        Self.lastSummary = summary
        logger.debug("A command-drag: \(summary, privacy: .public)")
    }

    // MARK: - Helpers

    /// Whether holzBar itself posted the event, as its own pointer drags and clicks do.
    private static func isPostedByHolzBar(_ event: NSEvent) -> Bool {
        guard let cgEvent = event.cgEvent else {
            return false
        }
        let marker = cgEvent.getIntegerValueField(.eventSourceUserData)
        return cgEvent.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier)
            || marker == HIDEventManager.menuBarActivationMarker
            || marker == MenuBarDragController.replayMarker
    }

    /// Whether a point is in the menu bar of a display other than the given one.
    private static func isInBarStrip(_ point: CGPoint, excluding displayID: CGDirectDisplayID) -> Bool {
        NSScreen.screens.contains { screen in
            let id = screen.displayID
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            let bounds = CGDisplayBounds(id)
            return id != displayID && bounds.contains(point) && point.y <= bounds.minY + height
        }
    }

    /// The bar of a display made of the items that are drawn: on screen, wider than 4 points and
    /// not of a concealed application, whose frame is stale.
    private static func bar(from items: [MenuBarItem], on displayID: CGDirectDisplayID, concealed: Set<pid_t>) -> MenuBarDrop.Bar? {
        let drawn = items.filter { $0.isOnScreen && $0.bounds.width > 4 && !concealed.contains($0.ownerPID) }
        return MenuBarDragController.bar(from: drawn, on: displayID, generation: .macOS27)
    }

    /// Whether a read holds what the decision needs: the dragged item and holzBar's icon.
    private static func isComplete(_ bar: MenuBarDrop.Bar?, draggedID: UInt32) -> Bool {
        guard let bar else {
            return false
        }
        return bar.items.contains { $0.id == draggedID } && bar.items.contains { $0.kind == .holzBarIcon }
    }

    private static func milliseconds(of duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds) * 1000 + Int(parts.attoseconds / 1_000_000_000_000_000)
    }

    private static func dropSection(_ section: MacOS27Section) -> MenuBarDrop.Section {
        switch section {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    private static func macOS27Section(_ section: MenuBarDrop.Section) -> MacOS27Section {
        switch section {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }
}
