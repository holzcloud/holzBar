//
//  SystemItemClickBridge27.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import Cocoa
import OSLog

/// Lets clicks reach the system items while items are concealed on macOS 27.
///
/// While an assessment-mode assertion is live, MenuBarAgent ignores clicks on the
/// clock (measured on macOS 27.0). The tap holds such a click back, releases the
/// assertions for a moment, and replays the click. `HIDEventManager` starts and stops it
/// with its other monitors; `AccessibilityBackend27` creates it.
@available(macOS 27.0, *)
@MainActor
final class SystemItemClickBridge27: SystemItemClickBridge {
    /// The shared app state.
    private weak var appState: AppState?

    /// What the tap's own thread decides a click from: a snapshot the main actor refreshes, and
    /// the presses held back and not yet released (see `ClickPairing`). Nothing in it is
    /// main-actor state (D-05).
    private let state = ClickBridgeState27()

    /// Lets the tap's callback, which runs off the main actor, reach the bridge only from a task
    /// on the main actor.
    private let box = BridgeBox()

    /// What keeps the snapshot current: an observation of the concealment flag, the clock
    /// setting and the full-screen flag, and the notifications that move the bar's geometry.
    private var snapshotLoop: ObservationLoop?
    private var snapshotTasks = [Task<Void, Never>]()

    /// System items that do not open from an Accessibility press, so a click on them has to
    /// go through MenuBarAgent. Seeded with what was measured on macOS 27.0; anything else
    /// that turns out to ignore the press joins them at its first click.
    private var systemItemsIgnoringPress: Set<String> = [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.battery",
        "com.apple.menuextra.wifi",
    ]

    /// Covers the concealed part of the bar while a click lifts concealment, so the hidden
    /// items do not flash into view (Thaw #1181).
    private let clockCover = ClockCover27()

    /// The panel holzBar saw open after a bridged click, so a second click on the same item is
    /// understood as the click that dismisses it. Forgotten whenever a click may have closed it
    /// unseen.
    private var panelMemory = ItemClick27.PanelMemory()

    /// Whether the bridge is started: set by ``start()``, cleared by ``stop()``.
    private var isRunning = false

    /// Looks again for Accessibility after the tap was left off for the lack of it.
    private var trustRetryTask: Task<Void, Never>?

    /// How long after the tap was left off, and between tries, holzBar looks again for
    /// Accessibility: 2 s, then 10 s after the tap was disabled.
    private static let trustRetryDelays: [Duration] = [.seconds(2), .seconds(8)]

    /// The tap, created on first use. It sees right and other clicks only to forget the panel
    /// they may close (a right click on the desktop closes Notification Center) and lets them
    /// through unchanged.
    ///
    /// Its callback runs on a thread of its own (D-05), so a busy main thread cannot make macOS
    /// disable it by timeout: it decides from `state` alone and starts a task on the main actor
    /// for everything else. The hidden default `MacOS27ClickBridgeOnMainThread` puts the same
    /// callback back on the main run loop, for a Mac where the thread misbehaves; it is read
    /// once, when the tap is created.
    private lazy var tap: EventTap = {
        let state = state
        let box = box
        let onMainThread = Defaults.bool(forKey: .macOS27ClickBridgeOnMainThread)
        Self.bridgeLogger.notice(
            "Click bridge: the tap runs on \(onMainThread ? "the main run loop" : "its own thread", privacy: .public)"
        )
        return EventTap(
            types: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown],
            location: .hidEventTap,
            placement: .headInsertEventTap,
            option: .defaultTap,
            runLoop: onMainThread ? .main : .ownThread(name: "com.holzcloud.holzBar.ClickBridge27"),
            disabledHandler: { _ in
                let action = state.tapWasDisabled()
                Task { @MainActor in
                    // A disabled tap saw no click that may have closed the panel.
                    box.bridge?.panelMemory.forget()
                    if action == .stop {
                        box.bridge?.retryTapAfterMissingAccessibility()
                    }
                }
                return action
            },
            callback: { event in
                let decision = state.decide(event)
                switch decision {
                case .pass:
                    return event
                case .swallow:
                    return nil
                case .passForgettingPanel:
                    Task { @MainActor in
                        box.bridge?.continueClick(decision)
                    }
                    return event
                case .hold(let hold):
                    // The press is held, so a bridge that is gone by the time the task runs
                    // still replays the click: it is never lost.
                    Task { @MainActor in
                        if let bridge = box.bridge {
                            bridge.continueClick(decision)
                        } else {
                            Self.replayClick(at: hold.barClick.location)
                        }
                    }
                    return nil
                }
            }
        )
    }()

    /// How many times macOS disabled the bridge's tap since holzBar started (a callback that
    /// took too long, or user input). Read by Copy Diagnostics.
    static var tapDisables: Int {
        ClickBridgeState27.disableCount
    }

    /// Creates a bridge for the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        isRunning = true
        trustRetryTask?.cancel()
        trustRetryTask = nil
        box.bridge = self
        refreshSnapshot()
        observeSnapshotInputs()
        tap.enable()
    }

    func stop() {
        isRunning = false
        trustRetryTask?.cancel()
        trustRetryTask = nil
        tap.disable()
        snapshotLoop?.cancel()
        snapshotLoop = nil
        snapshotTasks.forEach { $0.cancel() }
        snapshotTasks.removeAll()
        // A stopped bridge decides nothing; every click passes.
        state.invalidate()
        // A stopped tap sees no release any more, so no held press waits for one.
        state.flush()
        // The stopped tap no longer sees the clicks that close the panel.
        panelMemory.forget()
    }

    /// Looks again for Accessibility, after the tap was disabled and left off because
    /// `AXIsProcessTrusted()` said no.
    ///
    /// That answer can be false for a moment (the permission database is read again, or a grant
    /// races the check) while the permission model never sees a change, so nothing else would
    /// start the tap before the next settled bar. The tap is enabled again at the first try that
    /// finds the permission; after the last, the permission observer of `HIDEventManager` is left
    /// to it.
    private func retryTapAfterMissingAccessibility() {
        guard isRunning else {
            return
        }
        trustRetryTask?.cancel()
        trustRetryTask = Task { [weak self] in
            for delay in Self.trustRetryDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, isRunning else {
                    return
                }
                guard !tap.isEnabled else {
                    return
                }
                if AXIsProcessTrusted() {
                    Self.bridgeLogger.notice("Click bridge: Accessibility is there again, enabling the tap")
                    tap.enable()
                    return
                }
            }
        }
    }

    // MARK: The snapshot the tap thread decides from

    /// Fills the snapshot the tap thread decides from (the main actor knows these facts, the
    /// tap thread must not ask for them).
    ///
    /// Runs when the bridge starts and whenever one of them changes: the concealment flag, the
    /// clock setting and the full-screen flag (observed), the item area, the display setup, the
    /// active space (notifications), and after a click in the bar. A click that arrives before a
    /// refresh lands decides on the last snapshot, and a snapshot gone stale is made good by
    /// `continueClick(_:)`, which replays instead of lifting concealment once it finds the items
    /// no longer concealed.
    func refreshSnapshot() {
        // A task the tap queued before the bridge stopped may still call this: a stopped bridge
        // decides nothing, so the snapshot must stay invalid.
        guard isRunning, let appState else {
            state.invalidate()
            return
        }
        var snapshot = ClickBridgeState27.Snapshot()
        snapshot.isValid = true
        snapshot.isConcealing = appState.concealer27.isConcealing
        snapshot.clockOpensNotificationCenter = appState.settings.general.clockOpensNotificationCenter
        snapshot.isFullscreenSpace = appState.activeSpace.isFullscreen
        snapshot.ownItemFrames = Self.ownControlItemFrames(appState: appState)
        let thickness = NSStatusBar.system.thickness
        for screen in NSScreen.screens {
            snapshot.barHeights[screen.displayID] = max(screen.frame.maxY - screen.visibleFrame.maxY, thickness)
        }
        state.update(snapshot)
    }

    /// Keeps the snapshot current until the bridge stops.
    private func observeSnapshotInputs() {
        guard let appState, snapshotLoop == nil else {
            return
        }
        struct Inputs: Equatable {
            var isConcealing: Bool
            var clockOpensNotificationCenter: Bool
            var isFullscreenSpace: Bool
        }
        snapshotLoop = ObservationLoop.observe {
            Inputs(
                isConcealing: appState.concealer27.isConcealing,
                clockOpensNotificationCenter: appState.settings.general.clockOpensNotificationCenter,
                isFullscreenSpace: appState.activeSpace.isFullscreen
            )
        } onChange: { [weak self] _ in
            self?.refreshSnapshot()
        }
        snapshotTasks = [
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .menuBarItemsAreaDidChange27) {
                    self?.refreshSnapshot()
                }
            },
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: NSApplication.didChangeScreenParametersNotification
                ) {
                    self?.refreshSnapshot()
                }
            },
            Task { [weak self] in
                for await _ in NSWorkspace.shared.notificationCenter.notifications(
                    named: NSWorkspace.activeSpaceDidChangeNotification
                ) {
                    self?.refreshSnapshot()
                }
            },
        ]
    }

    /// Times the steps of a bridged click, which happen on both opening and closing a panel.
    private static let bridgeLogger = Logger(category: "ClickBridge27")

    /// Carries what the main actor owes a click after the tap thread decided it.
    ///
    /// A click let through only notes the bar click and forgets the panel it may have closed. A
    /// held press is bridged here: the same steps the main run loop's callback took after its
    /// decision.
    private func continueClick(_ decision: ClickBridgeState27.Decision) {
        switch decision {
        case .pass, .swallow:
            return
        case .passForgettingPanel(let barClick):
            panelMemory.forget()
            if let barClick, let appState {
                recordBarClick(barClick, appState: appState)
                // The bar's geometry may have moved since the last refresh.
                refreshSnapshot()
            }
        case .hold(let hold):
            guard let appState else {
                // The press is held and its release is taken, so the click is replayed whatever.
                Self.replayClick(at: hold.barClick.location)
                return
            }
            recordBarClick(hold.barClick, appState: appState)
            bridgeHeldClick(hold, appState: appState)
        }
    }

    /// Lifts concealment for a press the tap held back, and replays it.
    private func bridgeHeldClick(_ hold: ClickBridgeState27.Hold, appState: AppState) {
        let concealer = appState.concealer27
        let location = hold.barClick.location
        // The tap decided from a snapshot: items that are no longer concealed need no lift, only
        // the click the tap held back, so a stale snapshot never costs the click.
        guard concealer.isConcealing else {
            Self.replayClick(at: location)
            return
        }
        // Control Centre opens from an Accessibility press even while items are concealed
        // (measured on macOS 27.0: its panel appears after about 177 ms). The clock, the
        // battery and Wi-Fi ignore the press, so for those the concealment is lifted and the
        // click replayed — and put back the moment their panel is up, rather than after a
        // fixed second and a half, which is what made every hidden item flash into view.
        let systemItem = MenuBarItemProvider27.systemItem(at: location)
        let mayOpenFromPress = systemItem.map { !self.systemItemsIgnoringPress.contains($0.identifier) } ?? false
        let taken = panelMemory.takeForBridgedClick()
        Task {
            // A click that lands while a panel is up is the click that dismisses it, and
            // Escape dismisses it just as well — with no lift of concealment at all. Lifting
            // for such a click brought every hidden item back on screen first, and the panel
            // only answered once MenuBarAgent had finished moving the bar: the icons appeared,
            // and the panel closed late behind them.
            // So a click on the item whose panel holzBar opened, while that panel's window is
            // still up, dismisses it with Escape. Only a panel holzBar saw open in a new window
            // is remembered, and any click the bridge lets through forgets it: that click may
            // have closed it, and a banner shows in the same window as the panel — same
            // process, same level, the size of the display (measured on macOS 27.0) — so the
            // window alone cannot say whether a panel is open. Escape goes to the panel's own
            // process only, and unless the panel's window really goes, the held-back click is
            // replayed, so it is never lost. A panel opened some other way is closed by the
            // replayed click, as it would be without holzBar.
            var step = ItemClick27.firstStep(
                remembered: taken.remembered,
                windows: Self.windowsForPanelCheck(),
                mayOpenFromPress: mayOpenFromPress
            )
            if case .dismiss(let panel) = step {
                let dismissStarted = ProcessInfo.processInfo.systemUptime
                let isPanelItem = systemItem?.identifier == panel.item
                let polls = ItemClick27.escapeAnswerPolls(for: panel, clickedItem: systemItem?.identifier)
                Self.postEscape(to: panel.ownerPID)
                let went = await Self.waitForPanelToGo(window: panel.window, polls: polls)
                let waited = (ProcessInfo.processInfo.systemUptime - dismissStarted) * 1000
                if went {
                    Self.bridgeLogger.debug(
                        "Click bridge: Escape closed the panel in \(waited, privacy: .public) ms (own item: \(isPanelItem, privacy: .public))"
                    )
                } else {
                    Self.bridgeLogger.debug(
                        "Click bridge: the panel stayed \(waited, privacy: .public) ms after Escape (own item: \(isPanelItem, privacy: .public)), replaying the click"
                    )
                }
                guard let next = ItemClick27.stepAfterDismissal(
                    of: panel,
                    clickedItem: systemItem?.identifier,
                    windowWent: went,
                    windows: Self.windowsForPanelCheck(),
                    mayOpenFromPress: mayOpenFromPress
                ) else {
                    return
                }
                step = next
            }
            if step == .press, let systemItem {
                let baseline = Self.windowNumbers()
                await Self.press(systemItem.element)
                if let opened = await Self.waitForOpenedPanel(item: systemItem.identifier, baseline: baseline, polls: 5) {
                    // Remembered here as well, or the next click on this item would dismiss
                    // its panel and open it again in the same breath.
                    self.panelMemory.remember(opened, openedBy: taken.click)
                    return
                }
                // Waiting for a panel that never comes only delays the click, so an item
                // that ignored the press is not asked again while holzBar runs.
                self.systemItemsIgnoringPress.insert(systemItem.identifier)
            }
            // The click is replayed the moment the assertion is really gone rather than on a
            // timer: releasing it queues behind other concealment work, and MenuBarAgent ignores
            // a click that arrives while the assertion still stands, which is why the clock
            // sometimes did nothing and opened on the second try. Nothing else is done before
            // the replay, so the click is as quick as the release allows.
            let bridgeStarted = ProcessInfo.processInfo.systemUptime
            Self.bridgeLogger.debug("Click bridge: holding the click, lifting concealment")
            self.clockCover.show(appState: appState)
            await concealer.suspendReleased(for: Self.clickRestoreDelay)
            let released = (ProcessInfo.processInfo.systemUptime - bridgeStarted) * 1000
            let baseline = Self.windowNumbers()
            Self.replayClick(at: location)
            // One bounded wait, past the concealment's return.
            self.clockCover.hide(after: .milliseconds(300))
            Self.bridgeLogger.debug("Click bridge: lifted in \(released, privacy: .public) ms, click replayed")
            // Notification Center's window appears about 166 ms after the click (measured on
            // macOS 27.0). The replay may as well have closed a panel opened some other way.
            let opened = await Self.waitForOpenedPanel(item: systemItem?.identifier, baseline: baseline, polls: 8)
            self.panelMemory.remember(opened, openedBy: taken.click)
        }
    }

    /// Notes a click in a display's menu bar in the diagnostics' click trace (see
    /// `BarClickTrace`): where it landed, which system item was there, whether the bridge took
    /// it, and the extent of the system items and of holzBar's own control items. Clicks below
    /// the bar are not noted.
    private func recordBarClick(_ barClick: ClickBridgeState27.BarClick, appState: AppState) {
        let location = barClick.location
        let ownFrames = barClick.ownFrames
        let systemFrames = barClick.systemFrames
        guard let display = barClick.display, location.y - CGDisplayBounds(display).minY < 40 else {
            return
        }
        // A frame without finite edges (`CGRect.null`) has no extent to log.
        func range(_ frame: CGRect) -> ClosedRange<Int>? {
            guard frame.minX.isFinite, frame.maxX.isFinite, abs(frame.minX) < 1e6, abs(frame.maxX) < 1e6 else {
                return nil
            }
            return Int(frame.minX.rounded())...max(Int(frame.minX.rounded()), Int(frame.maxX.rounded()))
        }
        let ownItems = ownFrames.compactMap(range)
        BarClickLog.trace.record(BarClickTrace.barClick(
            seconds: BarClickLog.seconds,
            x: Int(location.x.rounded()),
            concealing: barClick.isConcealing,
            item: MenuBarItemProvider27.systemItem(at: location)?.identifier,
            bridged: barClick.bridged,
            systemItems: systemFrames.compactMap(range).sorted { $0.lowerBound < $1.lowerBound },
            ownItems: ownItems.sorted { $0.lowerBound < $1.lowerBound },
            overflow: MenuBarItemProvider27.overflowButtonFrame().flatMap(range)
        ))
    }

    /// The frames of holzBar's own control items, whose clicks are holzBar's own.
    ///
    /// The control items report AppKit frames; clicks and the system items' frames are in
    /// the coordinates of the top left of the primary display, so the frames are converted.
    private static func ownControlItemFrames(appState: AppState) -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            return []
        }
        return [MenuBarSection.Name.visible, .hidden, .alwaysHidden].compactMap { name in
            appState.menuBarManager.controlItem(withName: name)?.frame.map {
                ClockBridgeZone27.quartzFrame(fromAppKit: $0, primaryHeight: primaryHeight)
            }
        }
    }

    /// How long concealment stays lifted around a replayed click.
    ///
    /// MenuBarAgent needs the lift to act on the click at all, and every millisecond of it is
    /// a millisecond of the bar moving: the items slide back in, then out again. The panel's
    /// own window appears about 166 ms after the click (measured on macOS 27.0), so a lift
    /// that ends around then has the bar settling while the panel animates, which is what made
    /// the animation stutter.
    ///
    /// Measured on macOS 27.0 with `Scripts/macos27/clock-restore.swift`, on both displays: a
    /// lift of 40 ms loses the click 6 times in 16, 60 ms once in 16, and 80, 100 and 120 ms
    /// each opened the panel 16 times in 16. So the floor is around 60 ms, and 120 ms keeps
    /// double that margin while still ending before the panel appears. The
    /// `MacOS27ClickRestoreDelay` default overrides it, in milliseconds, for measuring.
    private static var clickRestoreDelay: Duration {
        let stored = Defaults.integer(forKey: .macOS27ClickRestoreDelay)
        return .milliseconds(stored > 0 ? min(max(stored, 30), 2000) : 120)
    }

    /// The window numbers currently on screen.
    private static func windowNumbers() -> Set<Int> {
        Set(WindowInfo.createWindows(option: .onScreen).map { Int($0.windowID) })
    }

    /// The processes that draw the system items' panels.
    ///
    /// Without this, the Dock passes for an open panel: its window stands at layer 20 and the
    /// full size of the display, and it is always there, so every click looked like a click
    /// that closes a panel and every wait for that panel to go ran into its timeout (measured
    /// on macOS 27.0: 12 clicks in a row judged "panel already open").
    private static let panelOwnerBundleIDs: Set<String> = [
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
    ]

    /// The windows on screen that could be a system item's panel, with the process that draws
    /// each, as `ItemClick27` wants them.
    private static func windowsForPanelCheck() -> [ItemClick27.PanelWindow] {
        let owners = Set(
            NSWorkspace.shared.runningApplications
                .filter { panelOwnerBundleIDs.contains($0.bundleIdentifier ?? "") }
                .map(\.processIdentifier)
        )
        return WindowInfo.createWindows(option: .onScreen)
            .filter { owners.contains($0.ownerPID) }
            .map { (number: Int($0.windowID), layer: $0.layer, height: $0.bounds.height, ownerPID: $0.ownerPID) }
    }

    /// Presses Escape in the given process, which dismisses an open system panel.
    ///
    /// Notification Center and Control Centre both answer Escape while items stay concealed, so
    /// a click that dismisses a panel needs no lift of concealment at all. Posted at the HID
    /// level, Escape reached whichever app had keyboard focus, so a dialog or sheet in front was
    /// cancelled or fullscreen ended; addressed to the panel's own process it reaches nothing
    /// else. Whether Notification Center and Control Centre act on an Escape sent to their
    /// process is not measured yet; when they do not, the click is replayed.
    private static func postEscape(to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.postToPid(pid)
        }
    }

    /// Waits for a system item's panel to appear in a new window, for at most the given number
    /// of 50 ms rounds. Polled: nothing announces another process's window.
    private static func waitForOpenedPanel(item: String?, baseline: Set<Int>, polls: Int) async -> ItemClick27.OpenPanel? {
        for _ in 0..<polls {
            try? await Task.sleep(for: .milliseconds(50))
            if let opened = ItemClick27.openedPanel(item: item, before: baseline, windows: windowsForPanelCheck()) {
                return opened
            }
        }
        return nil
    }

    /// Waits for the given panel window to leave the screen, for at most the given number of
    /// 50 ms rounds.
    ///
    /// - Returns: Whether it went.
    private static func waitForPanelToGo(window: Int, polls: Int) async -> Bool {
        for _ in 0..<polls {
            try? await Task.sleep(for: .milliseconds(50))
            if !ItemClick27.panelIsOnScreen(window: window, windows: windowsForPanelCheck()) {
                return true
            }
        }
        return false
    }

    /// Waits until the given panel window leaves the screen, checking it on the schedule of
    /// `ItemClick27.panelWatchInterval(elapsed:)`: 4 times a second for the first 10 s, then
    /// once a second, for at most 10 minutes. Polled: nothing announces another process's
    /// window; a cancelled task stops watching at once, and so does a watch that `isCurrent`
    /// no longer owns.
    private static func watchPanelUntilGone(window: Int, isCurrent: () -> Bool) async {
        let start = ContinuousClock.now
        while let interval = ItemClick27.panelWatchInterval(elapsed: ContinuousClock.now - start) {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            if !isCurrent() || !ItemClick27.panelIsOnScreen(window: window, windows: windowsForPanelCheck()) {
                return
            }
        }
    }

    /// Presses an Accessibility element off the main thread, which the call can block.
    private static func press(_ element: AXUIElement) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
                continuation.resume()
            }
        }
    }

    // MARK: Opened from the holzBar Shelf

    /// The hidden system items that a click on a Shelf tile is opening now, until its panel was
    /// found or not.
    private static var itemsOpenedFromShelf = Set<String>()

    /// The latest click from the Shelf on each hidden system item whose panel is still watched.
    /// A new click on the same tile ends the watch of the earlier one, so a close the watch
    /// missed never swallows the clicks on that tile for the rest of the 10 minutes.
    private static var shelfClickGenerations = [String: Int]()

    /// Opens a system item the user hid, from its tile in the holzBar Shelf.
    ///
    /// The item is lifted for a moment, clicked where macOS draws it with a click the tap lets
    /// through, and put away again once its panel is gone. Every exit after the show has begun
    /// ends the temporary show exactly once.
    ///
    /// - Parameters:
    ///   - item: The system item to open.
    ///   - shelfDisplayID: The display the Shelf was on, whose menu bar must be the active one.
    ///   - appState: The shared app state.
    static func openFromShelf(_ item: SystemItem27, shelfDisplayID: CGDirectDisplayID?, appState: AppState) async {
        let key = SystemItems27.concealedKey(for: item)
        // A second click while the first is still waiting for its panel starts nothing.
        guard itemsOpenedFromShelf.insert(key).inserted else {
            return
        }
        var isOpening = true
        defer {
            if isOpening {
                itemsOpenedFromShelf.remove(key)
            }
        }
        let identifier = item.accessibilityIdentifier
        let concealer = appState.concealer27

        // The menu bar of the Shelf's display must be active before the item is shown, while
        // the spot to click is still empty.
        await ItemClicker27.activateMenuBarIfNeeded(shelfDisplayID: shelfDisplayID, appState: appState)

        let shown = await concealer.showTemporarily(bundleID: key)
        defer {
            concealer.endTemporaryShow(bundleID: key)
        }
        // This click takes the watch over from an earlier one on the same tile, once its own show
        // holds the item, so the item is never put away in between.
        let generation = (shelfClickGenerations[key] ?? 0) &+ 1
        shelfClickGenerations[key] = generation
        defer {
            if shelfClickGenerations[key] == generation {
                shelfClickGenerations[key] = nil
            }
        }
        if shown {
            // A shown item is drawn 0.4 to 0.6 s after the change that allows it lands (measured).
            try? await Task.sleep(for: .milliseconds(600))
        } else {
            bridgeLogger.notice("A hidden system item was not shown in time")
        }

        _ = await MenuBarItemProvider27.items()
        let baseline = windowNumbers()
        if shown, let frame = MenuBarItemProvider27.systemItemFrame(identifier: identifier) {
            let original = CGEvent(source: nil)?.location
            replayClick(at: CGPoint(x: frame.midX, y: frame.midY))
            if let original {
                _ = CGWarpMouseCursorPosition(original)
            }
        } else if let element = MenuBarItemProvider27.systemItemElement(identifier: identifier) {
            await press(element)
        } else {
            bridgeLogger.error("A hidden system item is neither drawn nor reachable through Accessibility")
            return
        }

        // Keep the item shown until its panel is gone, watched on the panel watch schedule. The
        // opening is over: another click on the tile may start now and ends this watch.
        let opened = await waitForOpenedPanel(item: identifier, baseline: baseline, polls: 8)
        itemsOpenedFromShelf.remove(key)
        isOpening = false
        if let opened {
            await watchPanelUntilGone(window: opened.window) {
                shelfClickGenerations[key] == generation
            }
        } else {
            try? await Task.sleep(for: .milliseconds(1500))
        }
        // "Hide opened items again after" counts from here, when the panel has closed.
        let delay = min(max(appState.settings.advanced.tempShowInterval, 0), 30)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    static func replayClick(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: .left
            ) else {
                continue
            }
            event.setIntegerValueField(.eventSourceUserData, value: ClickBridgeState27.replayedClickMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}

@available(macOS 27.0, *)
extension SystemItemClickBridge27 {
    /// Lets the tap's callback, which runs off the main actor, reach the bridge, and only from a
    /// task on the main actor: the reference is set and read there.
    nonisolated final class BridgeBox: @unchecked Sendable {
        weak var bridge: SystemItemClickBridge27?
    }
}
