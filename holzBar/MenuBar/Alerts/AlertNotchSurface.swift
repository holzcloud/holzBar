//
//  AlertNotchSurface.swift
//  holzBar
//

import AppKit
import Observation
import SwiftUI

/// The alert in the closed notch for every user: a small panel of its own that draws the widened
/// notch while the Notch hub module is off (D-07, ALRT-02).
///
/// The widened notch exists only inside ``NotchHubController``, and only while the hub module is
/// on, so an alert would reach nobody who does not use the hub. A live-only mode of that
/// controller was rejected (research Pattern 4); this surface reuses what is pure instead: the
/// Core geometry (``NotchHubGeometry/live(display:room:)``), the black ``IslandShape`` and
/// ``IslandLiveView``. It draws black with no glass, the live shape's corners and its free-span
/// rule, the symbol left of the camera and the short value right of it, never a title, a detail or
/// a name. It asks for no permission.
///
/// It shows on the display where the hub shows (``NotchHubController/preferredScreen()``), and it
/// hides where the hub hides: in a fullscreen space, with the menu bar hidden, while the screen is
/// mirrored or shared, and on a display the hub's setting excludes (``NotchHubPolicy``, T-95-07).
/// Its panel is the hub's non-activating panel and never takes the keyboard (T-95-08).
///
/// On a bar so crowded that no free span is left beside the notch, the live shape does not exist
/// and an alert must not vanish: the surface then draws a detached pill below the notch, and only
/// an alert does (``NotchHubGeometry/detachedAlert(display:valueWidth:)``, UI-SPEC A3). It does so
/// with the hub off, and with the hub on while the hub cannot draw its live state; where the hub
/// can, the hub draws the alert and the surface stays away, so exactly one of them shows it. The
/// detached form also serves the indicator flashes of the Indicators module (H2), which keep a
/// surface of their own; the countdown and the notification count never fall back to it.
///
/// Nothing exists while nothing is to show: no panel, no task and no observation. While an alert is
/// live the surface follows what moves its place (the active space, the displays, the free menu bar,
/// a fullscreen space and a hidden menu bar) and waits once for the next time the board changes; it
/// runs no timer.
@MainActor
final class AlertNotchSurface {
    private weak var appState: AppState?

    /// The panel, created when something shows and released when it has gone.
    private var panel: NotchHubPanel?
    private let state = AlertSurfaceState()
    /// The activities of the alerts module, as the manager last handed them over.
    private var activities: [LiveActivity] = []
    private var phase = Phase.hidden
    private var placement: Placement?
    /// The key of the activity VoiceOver heard last, so each one is read once.
    private var announcedKey: String?

    /// Follows what moves the alert's place, only while an alert is live.
    private var inputsLoop: ObservationLoop?
    private var followTasks = [Task<Void, Never>]()
    /// The one wait until the board changes by itself: a widening that ends or a done state that
    /// leaves.
    private var expiryTask: Task<Void, Never>?
    private var expiryGeneration = 0
    /// Counts the transitions, so that a wait of an earlier one never changes a later one.
    private var transitionGeneration = 0
    /// The one wait that shrinks the panel to the shape once the spring has settled, or that orders
    /// it out once the closing has finished.
    private var transitionTask: Task<Void, Never>?

    private enum Phase {
        case hidden
        case open
        case closing
    }

    /// Where the alert is: the display and the live shape on it.
    private struct Placement: Equatable {
        var screenID: CGDirectDisplayID
        var screenFrame: CGRect
        var layout: NotchHubGeometry.LiveLayout
    }

    /// What moves the alert's place, read inside the observation.
    private struct Inputs: Equatable {
        var isFullscreenSpace: Bool
        var isMenuBarHidden: Bool
        var room: NotchHubGeometry.LiveRoom?
        var isHubActive: Bool
        var isHubOpen: Bool

        static let none = Inputs(isFullscreenSpace: false, isMenuBarHidden: false, room: nil, isHubActive: false, isHubOpen: false)
    }

    /// How long the panel stays larger than the shape after it opens, for the spring's overshoot.
    private static let settleDelay = Duration.milliseconds(1_200)
    private static let reducedSettleDelay = Duration.milliseconds(300)
    private static let closeDelay = Duration.milliseconds(900)
    private static let reducedCloseDelay = Duration.milliseconds(250)

    init(appState: AppState) {
        self.appState = appState
        state.onTap = { [weak self] in
            // The click is handled after the view's own action has returned, because it may
            // change what is on screen.
            Task { @MainActor in
                self?.alertWasClicked()
            }
        }
    }

    // MARK: Updating

    /// Takes the alerts the module holds now and shows, moves or ends the widened notch for them.
    func update(activities: [LiveActivity]) {
        self.activities = activities
        reconcile()
    }

    /// Takes everything away at once: the panel, the observation and the waits.
    func hide() {
        activities = []
        announcedKey = nil
        stopFollowing()
        cancelExpiry()
        tearDownPanel()
    }

    /// Works out the board and the place, and brings the panel in line with them: it opens, follows
    /// the board and the place, or closes.
    private func reconcile() {
        guard let appState else {
            hide()
            return
        }
        let board = HubActivityBoard.board(activities, now: .now, forClosedNotch: true)
        guard board.compact != nil else {
            // Nothing is live in the closed notch any more: the next alert is announced afresh.
            announcedKey = nil
            cancelExpiry()
            stopFollowing()
            close()
            return
        }
        armExpiry(at: board.nextExpiry)
        startFollowing()
        let hub = appState.notchHub
        // An open hub shows the alert in its right pill and in the Live activities list.
        guard !hub.isOpen else {
            close()
            return
        }
        guard
            let screen = hub.preferredScreen(),
            NotchHubPolicy.blockReason(hub.policyEnvironment(of: screen, appState: appState), trigger: .compact) == nil
        else {
            close()
            return
        }
        let display = hub.display(of: screen)
        guard let seed = NotchHubGeometry.seed(display: display) else {
            close()
            return
        }
        let live = NotchHubGeometry.live(
            display: display,
            room: NotchHubLiveRoom.room(on: screen, display: display, appState: appState)
        )
        // With the hub on, the hub draws the widened notch wherever it has a live shape.
        if hub.isActive, live != nil {
            close()
            return
        }
        // No free span beside the notch: the alert hangs detached below it (UI-SPEC A3).
        guard let layout = live ?? NotchHubGeometry.detachedAlert(display: display, valueWidth: Self.valueWidth(of: board)) else {
            close()
            return
        }
        show(
            board: board,
            placement: Placement(screenID: screen.displayID, screenFrame: screen.frame, layout: layout),
            seed: seed
        )
    }

    /// How wide the value area of the detached pill must be for the value the board shows now, in
    /// points: the live value's text in its own font (digits of equal width) or, for a flash that
    /// carries one, the wider of the value and its width sample, and the `+n` badge when more
    /// alerts are live. The geometry holds it between its limits.
    private static func valueWidth(of board: HubActivityBoard.Board) -> Double {
        guard let state = HubLiveState.make(board: board, now: .now) else {
            return 0
        }
        func width(of text: String, size: Double, weight: NSFont.Weight) -> Double {
            let font = NSFont.monospacedDigitSystemFont(ofSize: CGFloat(size), weight: weight)
            return Double((text as NSString).size(withAttributes: [.font: font]).width.rounded(.up))
        }
        var total: Double
        switch state.trailing {
        case .countdown:
            total = width(of: "00:00", size: DesignTokens.Island.liveValueSize, weight: .semibold)
        case .percent(let percent):
            total = width(of: (Double(percent) / 100).formatted(.percent), size: DesignTokens.Island.liveValueSize, weight: .semibold)
        case .word(let word):
            total = width(of: word, size: DesignTokens.Island.liveValueSize, weight: .semibold)
            // A flash names the widest text its value takes, so the pill keeps one width while the
            // value changes (D-10).
            if let sample = board.compact?.flash?.widthSample {
                total = max(total, width(of: sample, size: DesignTokens.Island.liveValueSize, weight: .semibold))
            }
        case .none:
            total = 0
        }
        if state.extraCount > 0 {
            // The badge: its text, the padding on both sides and the space before it.
            total += width(of: "+\(state.extraCount)", size: DesignTokens.Hub.pillTextSize, weight: .semibold)
                + 3 * DesignTokens.Spacing.xs
        }
        return total
    }

    // MARK: Showing

    private func show(board: HubActivityBoard.Board, placement newPlacement: Placement, seed: NotchHubGeometry.Rect) {
        announce(board.compact)
        if phase == .open, panel != nil {
            state.board = board
            if placement != newPlacement {
                place(newPlacement)
            }
            return
        }
        open(board: board, placement: newPlacement, seed: seed)
    }

    /// Opens the widened notch: the width grows from the notch's with the live state's spring, then
    /// the symbol and the value fade in. A detached shape, and any shape under Reduce Motion, fades
    /// in instead (the values and the tints never animate).
    private func open(board: HubActivityBoard.Board, placement newPlacement: Placement, seed: NotchHubGeometry.Rect) {
        let layout = newPlacement.layout
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fades = layout.isDetached || reduceMotion
        let panel = self.panel ?? makePanel()
        let continuesClosing = panel.isVisible && placement?.screenID == newPlacement.screenID
        transitionTask?.cancel()
        transitionGeneration += 1
        let generation = transitionGeneration
        phase = .open
        placement = newPlacement
        state.board = board
        let canvas = fades
            ? layout.shape
            : NotchHubGeometry.transitionFrame(
                from: seed,
                to: layout.shape,
                displayWidth: Double(newPlacement.screenFrame.width)
            )
        if continuesClosing {
            // A closing that is turned around keeps what it has drawn.
            state.layout = layout
            state.canvas = canvas
        } else {
            state.prepare(layout: layout, canvas: canvas, seed: fades ? nil : seed)
        }
        setPanelFrame(canvas, on: newPlacement.screenFrame)
        panel.orderFrontRegardless()
        // Lay the starting shape out first, without animation, so that the widening starts from it.
        panel.contentView?.layoutSubtreeIfNeeded()
        withAnimation(reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandOpenWidth) {
            state.settleOpen(reduceMotion: reduceMotion)
        }
        let delay = reduceMotion ? Self.reducedSettleDelay : Self.settleDelay
        transitionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.openSettled(generation)
        }
    }

    /// The spring has settled: the panel is exactly the shape, so it covers nothing else.
    private func openSettled(_ generation: Int) {
        guard generation == transitionGeneration, phase == .open, let placement else {
            return
        }
        transitionTask = nil
        state.moveCanvas(placement.layout.shape)
        setPanelFrame(placement.layout.shape, on: placement.screenFrame)
    }

    /// Puts the shape somewhere else at once: another display, or another free menu bar.
    private func place(_ newPlacement: Placement) {
        placement = newPlacement
        state.place(layout: newPlacement.layout)
        setPanelFrame(newPlacement.layout.shape, on: newPlacement.screenFrame)
        panel?.orderFrontRegardless()
    }

    // MARK: Closing

    /// Takes the shape back into the notch (or fades it) and then the panel away.
    private func close() {
        guard phase == .open, panel != nil, let placement else {
            return
        }
        phase = .closing
        transitionTask?.cancel()
        transitionGeneration += 1
        let generation = transitionGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if placement.layout.isDetached || reduceMotion {
            withAnimation(HolzBarTheme.Motion.reduced) {
                state.fadeOut()
            }
        } else if let seed = NotchHubGeometry.seed(display: displayForClosing(on: placement)) {
            let spring = HolzBarTheme.Motion.islandClose.delay(DesignTokens.Island.contentOutDuration)
            withAnimation(spring) {
                state.close(into: seed)
            }
        } else {
            withAnimation(HolzBarTheme.Motion.reduced) {
                state.fadeOut()
            }
        }
        let delay = reduceMotion ? Self.reducedCloseDelay : Self.closeDelay
        transitionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.closeFinished(generation)
        }
    }

    /// The display of a placement as the geometry reads it, for the notch the shape returns into.
    private func displayForClosing(on placement: Placement) -> NotchHubGeometry.Display {
        guard
            let appState,
            let screen = NSScreen.screens.first(where: { $0.displayID == placement.screenID })
        else {
            return NotchHubGeometry.Display(width: 0, height: 0, menuBarHeight: 0, notch: nil, island: nil)
        }
        return appState.notchHub.display(of: screen)
    }

    private func closeFinished(_ generation: Int) {
        guard generation == transitionGeneration, phase == .closing else {
            return
        }
        tearDownPanel()
    }

    /// Orders the panel out and drops it.
    private func tearDownPanel() {
        transitionTask?.cancel()
        transitionTask = nil
        transitionGeneration += 1
        guard panel != nil else {
            phase = .hidden
            placement = nil
            return
        }
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        phase = .hidden
        placement = nil
        state.reset()
    }

    // MARK: Panel

    private func makePanel() -> NotchHubPanel {
        let panel = NotchHubPanel()
        // It never takes the keyboard: `acceptsKeyboard` stays at its default, false (T-95-08).
        panel.applyDarkAppearance()
        panel.contentView = AlertHostingView(view: AlertNotchView(state: state))
        self.panel = panel
        return panel
    }

    /// Sets the panel's frame from a rectangle in the display's coordinates, the conversion the hub
    /// uses.
    private func setPanelFrame(_ rect: NotchHubGeometry.Rect, on screenFrame: CGRect) {
        let flipped = NotchHubGeometry.flipped(rect, displayHeight: Double(screenFrame.height))
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

    // MARK: Following

    /// Follows what moves the alert's place while an alert is live: a fullscreen space, a hidden
    /// menu bar and the free menu bar through an observation, and the active space, the displays and
    /// the status items' edge through three notification tasks.
    private func startFollowing() {
        guard inputsLoop == nil else {
            return
        }
        inputsLoop = ObservationLoop.observe({ [weak self] in
            self?.inputs() ?? .none
        }, onChange: { [weak self] _ in
            self?.reconcile()
        })
        followTasks = [
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                    self?.activeSpaceDidChange()
                }
            },
            Task { [weak self] in
                let center = NotificationCenter.default
                for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                    self?.reconcile()
                }
            },
            Task { [weak self] in
                // A read of the status items' edge on macOS 27 that moved although the item cache
                // compares equal.
                for await _ in NotificationCenter.default.notifications(named: .menuBarItemsAreaDidChange27) {
                    self?.reconcile()
                }
            },
        ]
    }

    private func stopFollowing() {
        inputsLoop?.cancel()
        inputsLoop = nil
        for task in followTasks {
            task.cancel()
        }
        followTasks.removeAll()
    }

    /// Reads, in one place, what the place depends on, so that the loop follows each of them.
    private func inputs() -> Inputs {
        guard let appState else {
            return .none
        }
        var room: NotchHubGeometry.LiveRoom?
        if let screen = appState.notchHub.preferredScreen() {
            room = NotchHubLiveRoom.room(
                on: screen,
                display: appState.notchHub.display(of: screen),
                appState: appState
            )
        }
        return Inputs(
            isFullscreenSpace: appState.activeSpace.isFullscreen,
            isMenuBarHidden: appState.menuBarManager.isMenuBarHiddenBySystem,
            room: room,
            isHubActive: appState.notchHub.isActive,
            isHubOpen: appState.notchHub.isOpen
        )
    }

    /// The panel moves to the active space only when it is ordered to the front
    /// (`.moveToActiveSpace`), and the place usually stays the same.
    private func activeSpaceDidChange() {
        reconcile()
        if phase == .open {
            panel?.orderFrontRegardless()
        }
    }

    // MARK: The wait for the board to change

    /// Arms the one wait: until the next moment the board changes by itself, then the board is
    /// worked out again. Replaces a wait already armed.
    private func armExpiry(at date: Date?) {
        cancelExpiry()
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
            reconcile()
        }
    }

    private func cancelExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        expiryGeneration += 1
    }

    // MARK: Accessibility

    /// Tells VoiceOver once that an alert started or recovered. The activity's own title is read.
    private func announce(_ activity: LiveActivity?) {
        guard let activity, activity.key != announcedKey else {
            return
        }
        announcedKey = activity.key
        if !activity.announcesItself {
            AccessibilityNotification.Announcement(activity.title).post()
        }
    }

    // MARK: Click

    /// A click on the alert: with the Notch hub on it opens the hub (the Live activities list in
    /// front), with the hub off it opens Settings on System alerts (D-18).
    private func alertWasClicked() {
        guard let appState else {
            return
        }
        if appState.notchHub.isActive {
            appState.notchHub.openForAlert()
            return
        }
        appState.navigationState.openModuleSettings(SystemAlertsSettings.moduleID)
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }
}

// MARK: - State

/// What the alert's view draws and how it moves: the black shape's place and size (which the
/// opening and the closing animate), its corner radii, and whether the symbol and the value show.
@MainActor
@Observable
private final class AlertSurfaceState {
    var board = HubActivityBoard.Board(listed: [], compact: nil, hiddenCount: 0, nextExpiry: nil)
    /// The live shape the alert comes to rest in, or `nil` while nothing shows.
    var layout: NotchHubGeometry.LiveLayout?
    /// The panel's frame, in the display's coordinates.
    var canvas = NotchHubGeometry.Rect(x: 0, y: 0, width: 0, height: 0)
    /// The black shape as drawn now.
    var drawnX = 0.0
    var drawnWidth = 0.0
    var topRadius = DesignTokens.Island.liveTopRadius
    var bottomRadius = DesignTokens.Island.liveBottomRadius
    var opacity = 1.0
    var showsContent = false
    /// The animation of the next change of ``showsContent``.
    var contentAnimation: Animation?
    @ObservationIgnored var onTap: (@MainActor () -> Void)?

    /// Starts an opening: at `seed`'s width with the notch's corners, or, with no seed, at the
    /// final shape and fully transparent, for a shape that fades in. Without animation.
    func prepare(layout: NotchHubGeometry.LiveLayout, canvas: NotchHubGeometry.Rect, seed: NotchHubGeometry.Rect?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.layout = layout
            self.canvas = canvas
            showsContent = false
            contentAnimation = nil
            if let seed {
                drawnX = seed.x
                drawnWidth = seed.width
                topRadius = DesignTokens.Island.notchTopRadius
                bottomRadius = DesignTokens.Island.notchBottomRadius
                opacity = 1
            } else {
                drawnX = layout.shape.x
                drawnWidth = layout.shape.width
                topRadius = DesignTokens.Island.liveTopRadius
                bottomRadius = DesignTokens.Island.liveBottomRadius
                opacity = 0
            }
        }
    }

    /// The opening's end values; called inside the animation.
    func settleOpen(reduceMotion: Bool) {
        guard let layout else {
            return
        }
        contentAnimation = reduceMotion ? HolzBarTheme.Motion.reduced : HolzBarTheme.Motion.islandContentIn
        drawnX = layout.shape.x
        drawnWidth = layout.shape.width
        topRadius = DesignTokens.Island.liveTopRadius
        bottomRadius = DesignTokens.Island.liveBottomRadius
        opacity = 1
        showsContent = true
    }

    /// The closing into the notch's rectangle; called inside the animation.
    func close(into seed: NotchHubGeometry.Rect) {
        contentAnimation = HolzBarTheme.Motion.islandContentOut
        showsContent = false
        drawnX = seed.x
        drawnWidth = seed.width
        topRadius = DesignTokens.Island.notchTopRadius
        bottomRadius = DesignTokens.Island.notchBottomRadius
    }

    /// The closing of a shape that fades; called inside the animation.
    func fadeOut() {
        contentAnimation = HolzBarTheme.Motion.reduced
        showsContent = false
        opacity = 0
    }

    /// Moves the panel's frame, at once and without animation. What is drawn keeps its place on the
    /// display.
    func moveCanvas(_ rect: NotchHubGeometry.Rect) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            canvas = rect
        }
    }

    /// Takes the final shape at once, with the panel exactly as large as it.
    func place(layout: NotchHubGeometry.LiveLayout) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            self.layout = layout
            canvas = layout.shape
            drawnX = layout.shape.x
            drawnWidth = layout.shape.width
            topRadius = DesignTokens.Island.liveTopRadius
            bottomRadius = DesignTokens.Island.liveBottomRadius
            opacity = 1
            showsContent = true
        }
    }

    func reset() {
        layout = nil
        showsContent = false
    }
}

// MARK: - View

/// The alert's view: the black live shape, with the lower edge outline under Increase Contrast, and
/// the hub's live content over it. The shape lies at its place on the display; the panel is its
/// canvas.
private struct AlertNotchView: View {
    let state: AlertSurfaceState

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let layout = state.layout {
                shape(layout)
                if state.showsContent {
                    IslandLiveView(
                        board: state.board,
                        layout: layout,
                        origin: CGPoint(
                            x: layout.shape.x - state.canvas.x,
                            y: layout.shape.y - state.canvas.y
                        )
                    ) {
                        state.onTap?()
                    }
                    // It fades in and out with the animation of ``AlertSurfaceState/contentAnimation``.
                    .transition(.opacity)
                }
            }
        }
        .frame(width: CGFloat(state.canvas.width), height: CGFloat(state.canvas.height), alignment: .topLeading)
        .animation(state.contentAnimation, value: state.showsContent)
    }

    private func shape(_ layout: NotchHubGeometry.LiveLayout) -> some View {
        let topRadius = CGFloat(state.topRadius)
        let bottomRadius = CGFloat(state.bottomRadius)
        return ZStack {
            IslandShape(topRadius: topRadius, bottomRadius: bottomRadius, convexTop: layout.isDetached)
                .fill(HolzBarTheme.Island.surface)
            if contrast == .increased {
                IslandLowerEdge(topRadius: topRadius, bottomRadius: bottomRadius, convexTop: layout.isDetached)
                    .stroke(HolzBarTheme.Island.edge, lineWidth: HolzBarTheme.Island.edgeWidth)
            }
        }
        .frame(width: CGFloat(state.drawnWidth), height: CGFloat(layout.shape.height))
        .opacity(state.opacity)
        .offset(x: CGFloat(state.drawnX - state.canvas.x), y: CGFloat(layout.shape.y - state.canvas.y))
        .accessibilityHidden(true)
    }
}

/// The hosting view of the alert's panel: no safe area of its own, and it takes the first click, so
/// that one click on the alert is enough while another app is in front.
private final class AlertHostingView: NSHostingView<AlertNotchView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(view: AlertNotchView) {
        super.init(rootView: view)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: AlertNotchView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
