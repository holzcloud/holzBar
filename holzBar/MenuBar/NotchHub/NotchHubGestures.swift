//
//  NotchHubGestures.swift
//  holzBar
//

import AppKit

/// The Notch hub's gestures (HUB-03, D-14): a scroll on the closed notch opens and closes the hub,
/// and a sideways swipe skips a track while Now Playing reports that something plays.
///
/// The object follows the Gestures switch itself and owns one scroll monitor only while the switch
/// is on; the hub creates it with the module and drops it with it, so nothing exists while either
/// is off. The monitor only listens: the local handler returns every event unchanged and the
/// global one observes, so another app's scrolling is never consumed, delayed or changed, and no
/// event is logged.
///
/// Every event is first tested against two places: the closed shape's area
/// (``HubScrollGesture/area(of:menuBarHeight:)``: the notch, or the top centre of a display without
/// one, never the wider hover zone) and the open hub's panel while its Now Playing tab is in
/// front. Anywhere else nothing happens and the gesture state is dropped. In one of them, the event
/// becomes one ``HubScrollGesture/Sample`` and only an action the Core type returns does anything.
@MainActor
final class NotchHubGestures {
    private weak var hub: NotchHubController?
    private weak var appState: AppState?

    /// Follows the Gestures switch.
    private var switchLoop: ObservationLoop?

    /// The scroll monitor; exists only while the switch is on.
    private var monitor: EventMonitor?

    /// Decides when a stream of scroll events is one swipe.
    private var gesture = HubScrollGesture()

    /// Whether the trackpad gesture that is going on began inside the area. A swipe that began in
    /// an app and slid up into the area never acts.
    private var beganInside = false

    init(hub: NotchHubController, appState: AppState) {
        self.hub = hub
        self.appState = appState
        switchLoop = ObservationLoop.observe { [weak appState] in
            appState?.settings.notchHub.gestures ?? false
        } onChange: { [weak self] isOn in
            self?.update(isOn: isOn)
        }
        update(isOn: appState.settings.notchHub.gestures)
    }

    /// Stops following the switch and removes the monitor.
    func stop() {
        switchLoop?.cancel()
        switchLoop = nil
        monitor?.stop()
        monitor = nil
        resetGesture()
    }

    // MARK: Monitor

    private func update(isOn: Bool) {
        guard isOn else {
            monitor?.stop()
            monitor = nil
            resetGesture()
            return
        }
        guard monitor == nil else {
            return
        }
        let monitor = EventMonitor.passive(for: .scrollWheel, scope: .universal) { [weak self] event in
            self?.handle(event)
        }
        monitor.start()
        self.monitor = monitor
    }

    private func resetGesture() {
        gesture.reset()
        beganInside = false
    }

    // MARK: Events

    private func handle(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        guard let hub, hub.isActive, let screen = screen(containing: location) else {
            resetGesture()
            return
        }
        let inNotch = isInNotch(location, on: screen, hub: hub)
        let inHub = isInNowPlayingHub(location, on: screen, hub: hub)
        guard inNotch || inHub else {
            resetGesture()
            return
        }
        let sample = HubScrollGesture.Sample(
            dx: Double(event.scrollingDeltaX),
            dy: Double(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            isInverted: event.isDirectionInvertedFromDevice,
            phase: Self.phase(event.phase),
            momentumPhase: Self.phase(event.momentumPhase),
            at: .now
        )
        if sample.isPrecise, sample.momentumPhase == .none {
            switch sample.phase {
            case .began:
                beganInside = true
            case .changed where !beganInside:
                // The swipe began elsewhere.
                return
            case .ended, .cancelled:
                beganInside = false
            default:
                break
            }
        }
        guard let action = gesture.offer(sample) else {
            return
        }
        perform(action, on: screen, hub: hub, inNotch: inNotch, inHub: inHub)
    }

    /// Does what a swipe asks, where it is allowed. Opening and closing belong to the closed shape's
    /// area; skipping belongs to the same area while the hub is closed and something plays, and to
    /// the whole open hub while its Now Playing tab is in front.
    private func perform(
        _ action: HubScrollGesture.Action,
        on screen: NSScreen,
        hub: NotchHubController,
        inNotch: Bool,
        inHub: Bool
    ) {
        switch action {
        case .open:
            if inNotch, !hub.isOpen {
                hub.openFromGesture(on: screen)
            }
        case .close:
            if inNotch, hub.isOpen, hub.screenID == screen.displayID {
                hub.close()
            }
        case .next, .previous:
            guard let nowPlaying = hub.runtime(NowPlayingRuntime.self) else {
                return
            }
            let forward = action == .next
            if hub.isOpen {
                if inHub {
                    nowPlaying.skip(forward: forward, showsFlash: false)
                }
            } else if inNotch, nowPlaying.contextSignal == .playing(true) {
                nowPlaying.skip(forward: forward, showsFlash: true)
            }
        }
    }

    // MARK: Geometry

    /// The screen the pointer is on, the top edge included. The top-edge row is part of the screen
    /// for a pointer, though `CGRect.contains` leaves it out. Cheap: a few frame reads, no layout.
    private func screen(containing location: CGPoint) -> NSScreen? {
        NSScreen.screens.first { Self.contains($0.frame, location) }
    }

    /// Whether the pointer is in the closed shape's area on the screen. Only the top row can hold
    /// the area, so a pointer lower than the menu bar or the notch is out before anything is worked
    /// out; the layout of the display is read only for a pointer in the top row.
    private func isInNotch(_ location: CGPoint, on screen: NSScreen, hub: NotchHubController) -> Bool {
        let frame = screen.frame
        let topRow = max(screen.safeAreaInsets.top, frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
        guard frame.maxY - location.y <= topRow else {
            return false
        }
        let display = hub.display(of: screen)
        guard let seed = NotchHubGeometry.seed(display: display) else {
            return false
        }
        let area = HubScrollGesture.area(of: seed, menuBarHeight: display.menuBarHeight)
        let local = NotchHubPolicy.localPoint(
            globalX: Double(location.x),
            globalY: Double(location.y),
            displayMinX: Double(frame.minX),
            displayMaxY: Double(frame.maxY)
        )
        return area.contains(x: local.x, y: local.y)
    }

    /// Whether the pointer is in the open hub's panel on its own screen while the Now Playing tab is
    /// in front.
    private func isInNowPlayingHub(_ location: CGPoint, on screen: NSScreen, hub: NotchHubController) -> Bool {
        guard
            hub.isOpen,
            hub.screenID == screen.displayID,
            hub.model.selectedID == NowPlayingRuntime.identifier,
            let frame = hub.visiblePanelFrame
        else {
            return false
        }
        return Self.contains(frame, location)
    }

    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func phase(_ phase: NSEvent.Phase) -> HubScrollGesture.Phase {
        if phase.contains(.began) || phase.contains(.mayBegin) {
            return .began
        }
        if phase.contains(.changed) || phase.contains(.stationary) {
            return .changed
        }
        if phase.contains(.ended) {
            return .ended
        }
        if phase.contains(.cancelled) {
            return .cancelled
        }
        return .none
    }
}
