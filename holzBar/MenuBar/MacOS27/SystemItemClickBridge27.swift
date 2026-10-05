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

    /// Until when the release of a held-back click is held back as well (see
    /// `handle(_:)`). The deadline keeps a release that never comes from
    /// swallowing an unrelated one later.
    private var heldBackReleaseUntil: ContinuousClock.Instant?

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

    /// The tap, created on first use.
    private lazy var tap = EventTap(
        types: [.leftMouseDown, .leftMouseUp],
        location: .hidEventTap,
        placement: .headInsertEventTap,
        option: .defaultTap
    ) { [weak self] _, event in
        guard let self else {
            return event
        }
        return handle(event)
    }

    /// Creates a bridge for the given app state.
    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        tap.enable()
    }

    func stop() {
        tap.disable()
        // The stopped tap no longer sees the clicks that close the panel.
        panelMemory.forget()
    }

    /// Marks the clicks holzBar replays, so the tap lets them through.
    private static let replayedClickMarker: Int64 = 0x1CE_27_C1C

    /// Times the steps of a bridged click, which happen on both opening and closing a panel.
    private static let bridgeLogger = Logger(category: "ClickBridge27")

    /// Handles a click the tap received; returns `nil` for a click that is held back.
    private func handle(_ event: CGEvent) -> CGEvent? {
        guard let appState else {
            return event
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayedClickMarker else {
            return event
        }
        if event.type == .leftMouseUp {
            // A press holzBar holds back has its release held back with it. MenuBarAgent would
            // otherwise be handed a release with no press behind it, moments before the
            // replayed click that carries both.
            guard let until = heldBackReleaseUntil, ContinuousClock.now < until else {
                heldBackReleaseUntil = nil
                return event
            }
            heldBackReleaseUntil = nil
            return nil
        }
        let concealer = appState.concealer27
        // The frames of the display the click landed on, so the clock of the display whose bar
        // is not active is recognised as well.
        let clickedDisplay = NSScreen.screens.first { CGDisplayBounds($0.displayID).contains(event.location) }?.displayID
        let framesOnDisplay = clickedDisplay.map { MenuBarItemProvider27.systemItemFrames(for: $0) } ?? []
        // The bar's rectangle is worked out only for a click that may be bridged at all.
        let menuBarRect = concealer.isConcealing ? clickedDisplay.flatMap { displayID in
            Self.visibleMenuBarRect(on: displayID, isFullscreenSpace: appState.activeSpace.isFullscreen)
        } : nil
        // The overflow button ("»") ignores clicks while concealed like the clock (Thaw #1195).
        let systemFrames = (framesOnDisplay.isEmpty ? MenuBarItemProvider27.systemItemFrames() : framesOnDisplay)
            + [MenuBarItemProvider27.overflowButtonFrame()].compactMap { $0 }
        guard ClockBridgeZone27.shouldBridge(
            click: event.location,
            systemItemFrames: systemFrames,
            isConcealing: concealer.isConcealing,
            menuBarRect: menuBarRect
        ) else {
            // A click let through may close the panel holzBar saw open (a click on the desktop
            // closes Notification Center), and nothing would tell.
            panelMemory.forget()
            return event
        }
        let location = event.location
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
                Self.postEscape(to: panel.ownerPID)
                let went = await Self.waitForPanelToGo(window: panel.window, polls: Self.escapeAnswerPolls)
                let waited = (ProcessInfo.processInfo.systemUptime - dismissStarted) * 1000
                if went {
                    Self.bridgeLogger.debug("Click bridge: Escape closed the panel in \(waited, privacy: .public) ms")
                } else {
                    Self.bridgeLogger.debug("Click bridge: the panel stayed \(waited, privacy: .public) ms after Escape, replaying the click")
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
        heldBackReleaseUntil = .now + .seconds(1)
        return nil
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

    /// How many 50 ms rounds a panel gets to answer Escape before the click is replayed
    /// instead: about 200 ms. Not measured on macOS 27 yet.
    private static let escapeAnswerPolls = 4

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

    /// Presses an Accessibility element off the main thread, which the call can block.
    private static func press(_ element: AXUIElement) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
                continuation.resume()
            }
        }
    }

    /// The rectangle of the given display's menu bar, or `nil` while the bar is not on
    /// screen.
    ///
    /// On a fullscreen space the bar shows only while the pointer reveals it, so it counts
    /// only while the window server's menu bar window is on screen (the window list, not
    /// Accessibility). Elsewhere the bar is the strip above the screen's visible frame, at
    /// least as tall as the status bar.
    private static func visibleMenuBarRect(on displayID: CGDirectDisplayID, isFullscreenSpace: Bool) -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)
        let height: CGFloat
        if isFullscreenSpace {
            guard let menuBarWindow = WindowInfo.menuBarWindow(for: displayID) else {
                return nil
            }
            height = menuBarWindow.bounds.height
        } else {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            height = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        }
        return CGRect(x: displayBounds.minX, y: displayBounds.minY, width: displayBounds.width, height: height)
    }

    private static func replayClick(at location: CGPoint) {
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
            event.setIntegerValueField(.eventSourceUserData, value: replayedClickMarker)
            event.post(tap: .cghidEventTap)
        }
    }
}
