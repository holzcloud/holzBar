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

    /// A press of the left button with Command held, on an application's item of the active bar.
    private struct Press {
        let draggedID: UInt32
        /// The application's layout key.
        let key: String
        /// The application's name, for the notice.
        let name: String
        /// The bar as the item cache held it at the press.
        let bar: MenuBarDrop.Bar
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

    /// Arms a press when the event is a Command-press on an application's item of the active bar.
    func pressed(_ event: NSEvent) {
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
        guard !Self.isPostedByHolzBar(event) else {
            return
        }
        guard
            !appState.activeSpace.isFullscreen,
            !appState.menuBarManager.isMenuBarHiddenBySystem,
            let displayID = Bridging.getActiveMenuBarDisplayID(),
            let point = event.cgEvent?.location ?? MouseHelpers.locationCoreGraphics
        else {
            return
        }
        let managed = appState.itemManager.itemCache.managedItems
        guard
            let bar = Self.bar(from: managed, on: displayID, concealed: appState.concealer27.concealedPIDs),
            let hit = bar.item(at: point),
            hit.kind == .app,
            let item = managed.first(where: { $0.windowID == hit.id }),
            let key = item.layoutKey27
        else {
            return
        }
        supersedeGesture()
        armed = Press(
            draggedID: hit.id,
            key: key,
            name: item.sourceApplication?.localizedName ?? item.displayName,
            bar: bar,
            point: point,
            displayID: displayID
        )
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
        // A click without movement decides at once, without a read.
        if abs(release.x - press.point.x) >= CommandDragSection.movementThreshold {
            guard await waitForBarToSettle() else {
                return
            }
            settled = await readBar(for: press)
            reads = 1
            if !Self.isComplete(settled, draggedID: press.draggedID) {
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
        let decision: CommandDragSection.Decision
        if reads > 0, Bridging.getActiveMenuBarDisplayID() != press.displayID {
            decision = .ignore(.otherDisplay)
        } else {
            decision = CommandDragSection.decide(
                draggedID: press.draggedID,
                press: press.bar,
                pressPoint: press.point,
                release: release,
                settled: settled
            )
        }
        let current = Self.dropSection(appState.concealer27.section(forKey: press.key))
        let outcome = CommandDragSection.outcome(for: decision, current: current, lock: nil)
        apply(outcome, press: press, appState: appState)
        let summary = CommandDragSection.summary(waitedMilliseconds: waited, reads: reads, decision: decision, outcome: outcome)
        record(summary)
        settleTask = nil
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

    /// Writes the section of an applied drop and tells the user.
    private func apply(_ outcome: CommandDragSection.Outcome, press: Press, appState: AppState) {
        guard case .apply(let from, let to) = outcome else {
            return
        }
        appState.concealer27.setSection(Self.macOS27Section(to), for: press.key)
        // A rule that controls the item has to look at it again.
        appState.automation.itemsWereArrangedByHand()
        let notice = CommandDragNotice.make(key: press.key, name: press.name, kind: .set(from: from, to: to))
        notices = CommandDragNotices.adding(notice, to: notices)
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
        return cgEvent.getIntegerValueField(.eventSourceUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier)
            || cgEvent.getIntegerValueField(.eventSourceUserData) == HIDEventManager.menuBarActivationMarker
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
