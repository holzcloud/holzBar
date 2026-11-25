//
//  ClickBridgeState27.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import OSLog
import os

/// What the click bridge's tap thread decides a click from, and the decision itself (D-05).
///
/// The tap of `SystemItemClickBridge27` runs its callback on a thread of its own, so a busy main
/// thread can no longer make macOS disable it by timeout. Everything the callback reads lives
/// here, behind locks, and none of it is main-actor state:
///
/// - a ``Snapshot`` of the few facts that only the main actor knows (whether items are
///   concealed, the clock's setting, the full-screen flag, the frames of holzBar's own items, the
///   bar heights). The main actor refreshes it whenever one of them changes; a missing
///   snapshot means the click passes.
/// - the ``ClickPairing`` of the held presses.
/// - the lock-protected frames of `MenuBarItemProvider27`.
///
/// ``decide(_:)`` only decides and records the press in the pairing. What needs the main actor
/// (the click trace, the panel memory, the replay) happens in a task the bridge starts after the
/// decision.
///
/// This type must never name the main actor's state, directly or through a helper: its methods
/// run on the tap's thread, and with Swift 6 and main-actor default isolation such a read
/// would wait for the main thread (RESEARCH, Pitfall 3).
@available(macOS 27.0, *)
nonisolated final class ClickBridgeState27: @unchecked Sendable {
    /// What the main actor tells the tap thread.
    struct Snapshot: Sendable {
        /// Whether the main actor has filled the snapshot in. Without it every click passes.
        var isValid = false

        /// Whether items are concealed right now.
        var isConcealing = false

        /// The setting "Open Notification Center from the clock".
        var clockOpensNotificationCenter = false

        /// Whether the active space is a full-screen space.
        var isFullscreenSpace = false

        /// The frames of holzBar's own control items, in the coordinates of click locations.
        var ownItemFrames: [CGRect] = []

        /// The height of each display's menu bar outside a full-screen space.
        var barHeights: [CGDirectDisplayID: CGFloat] = [:]
    }

    /// A click in the menu bar, for the click trace and the main actor's follow-up.
    struct BarClick: Sendable {
        let location: CGPoint
        let display: CGDirectDisplayID?
        let systemFrames: [CGRect]
        let ownFrames: [CGRect]
        let isConcealing: Bool
        let bridged: Bool
    }

    /// A press the tap held back, for the main actor to replay.
    struct Hold: Sendable {
        let barClick: BarClick
    }

    /// What the tap does with an event, and what is left for the main actor.
    enum Decision: Sendable {
        /// Let the event through; nothing more to do.
        case pass

        /// Let the event through; it may close the panel holzBar saw open, so the main actor
        /// forgets it, and notes a click in the menu bar in the click trace.
        case passForgettingPanel(BarClick?)

        /// Take the release of a held press; the replayed click carries it.
        case swallow

        /// Hold the press back; the main actor lifts concealment and replays the click.
        case hold(Hold)
    }

    /// Marks the clicks holzBar replays, so the tap lets them through.
    static let replayedClickMarker: Int64 = 0x1CE_27_C1C

    /// How many times macOS disabled the bridge's tap since holzBar started.
    private static let disables = OSAllocatedUnfairLock(initialState: 0)

    /// How many times macOS disabled the bridge's tap since holzBar started (a callback that took
    /// too long, or user input). Read by Copy Diagnostics.
    static var disableCount: Int {
        disables.withLock { $0 }
    }

    private static let logger = Logger(category: "ClickBridge27")

    private let snapshot = OSAllocatedUnfairLock(initialState: Snapshot())
    private let pairing = OSAllocatedUnfairLock(initialState: ClickPairing())

    /// Replaces the snapshot. Called on the main actor.
    func update(_ newSnapshot: Snapshot) {
        snapshot.withLock { $0 = newSnapshot }
    }

    /// Marks the snapshot invalid, so every click passes until the next ``update(_:)``.
    func invalidate() {
        snapshot.withLock { $0 = Snapshot() }
    }

    /// Lets every held press go, for when the tap is stopped or disabled.
    ///
    /// - Returns: The numbers of the presses that were held.
    @discardableResult
    func flush() -> [Int64] {
        pairing.withLock { $0.flush() }
    }

    /// Answers macOS disabling the tap: no held press waits for a release any more, and the tap
    /// is enabled again only while holzBar still has Accessibility.
    ///
    /// The flushed presses are replayed by their running bridge task or were never bridged, so
    /// their late releases must pass. Without Accessibility an enabled tap would keep failing and
    /// could hold input back, so it stays off; the health check of `HIDEventManager` starts the
    /// bridge again when the permission comes back.
    func tapWasDisabled() -> EventTap.DisabledAction {
        Self.disables.withLock { $0 += 1 }
        let flushed = flush()
        if !flushed.isEmpty {
            Self.logger.notice(
                "Click bridge: the tap was disabled, \(flushed.count, privacy: .public) held press(es) let go"
            )
        }
        guard AXIsProcessTrusted() else {
            Self.logger.notice("Click bridge: the tap was disabled and Accessibility is gone, leaving it off")
            return .stop
        }
        return .reenable
    }

    /// Decides what the tap does with a click.
    ///
    /// Runs on the tap's thread, in microseconds: locks, the lock-protected frames of
    /// `MenuBarItemProvider27`, and (only on a full-screen space, only for a click near the top
    /// edge) one window list.
    func decide(_ event: CGEvent) -> Decision {
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayedClickMarker else {
            return .pass
        }
        let expired = pairing.withLock { $0.expire(at: .now) }
        if !expired.isEmpty {
            Self.logger.debug(
                "Click bridge: \(expired.count, privacy: .public) held press(es) never saw their release and were let go"
            )
        }
        switch event.type {
        case .rightMouseDown, .otherMouseDown:
            // Never bridged, but it may close the panel holzBar saw open, and nothing would tell.
            return .passForgettingPanel(nil)
        case .leftMouseUp:
            // A press holzBar holds back has its release held back with it. MenuBarAgent would
            // otherwise be handed a release with no press behind it, moments before the replayed
            // click that carries both. Only the release with the press's own event number is
            // taken.
            let number = event.getIntegerValueField(.mouseEventNumber)
            return pairing.withLock { $0.release(number: number) } == .swallowRelease ? .swallow : .pass
        case .leftMouseDown:
            return decidePress(event)
        default:
            return .pass
        }
    }

    /// Decides a left press from the snapshot.
    private func decidePress(_ event: CGEvent) -> Decision {
        let state = snapshot.withLock { $0 }
        guard state.isValid else {
            // No snapshot (not filled in yet, or the bridge stopped): never decide on nothing.
            return .pass
        }
        let location = event.location
        // The frames of the display the click landed on, so the clock of the display whose bar is
        // not active is recognised as well.
        let display = Self.display(at: location, knownTo: state)
        let framesOnDisplay = display.map { MenuBarItemProvider27.systemItemFrames(for: $0) } ?? []
        // The bar's rectangle is worked out only for a click that may be bridged at all.
        let menuBarRect = state.isConcealing ? display.flatMap { Self.visibleMenuBarRect(on: $0, click: location, state: state) } : nil
        // The overflow button ("»") ignores clicks while concealed like the clock (Thaw #1195).
        let systemFrames = (framesOnDisplay.isEmpty ? MenuBarItemProvider27.systemItemFrames() : framesOnDisplay)
            + [MenuBarItemProvider27.overflowButtonFrame()].compactMap { $0 }
        let isInZone = ClockBridgeZone27.shouldBridge(
            click: location,
            systemItemFrames: systemFrames,
            ownItemFrames: state.ownItemFrames,
            isConcealing: state.isConcealing,
            menuBarRect: menuBarRect
        )
        let barClick = BarClick(
            location: location,
            display: display,
            systemFrames: systemFrames,
            ownFrames: state.ownItemFrames,
            isConcealing: state.isConcealing,
            bridged: isInZone
        )
        guard isInZone else {
            // A click let through may close the panel holzBar saw open (a click on the desktop
            // closes Notification Center), and nothing would tell.
            return .passForgettingPanel(barClick)
        }
        // The user can leave the clock's click to macOS ("Open Notification Center from the
        // clock"): it then reaches MenuBarAgent unchanged, which ignores it while items are
        // concealed. The other system items stay bridged.
        let identifier = MenuBarItemProvider27.systemItem(at: location)?.identifier
        guard ClockClickPolicy.bridges(
            item: identifier,
            clockOpensNotificationCenter: state.clockOpensNotificationCenter
        ) else {
            return .passForgettingPanel(BarClick(
                location: location,
                display: display,
                systemFrames: systemFrames,
                ownFrames: state.ownItemFrames,
                isConcealing: state.isConcealing,
                bridged: true
            ))
        }
        let number = event.getIntegerValueField(.mouseEventNumber)
        pairing.withLock { $0.hold(number: number, at: .now) }
        return .hold(Hold(barClick: barClick))
    }

    /// The display a point lies on, among the displays the snapshot has a bar height for.
    private static func display(at point: CGPoint, knownTo state: Snapshot) -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 4)
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, UInt32(displays.count), &displays, &count) == .success else {
            return nil
        }
        return displays.prefix(Int(count)).first { state.barHeights[$0] != nil }
    }

    /// The rectangle of the given display's menu bar, or `nil` while the bar is not on screen.
    ///
    /// On a fullscreen space the bar shows only while the pointer reveals it, so it counts only
    /// while the window server's menu bar window is on screen (the window list, not
    /// Accessibility). Elsewhere the bar is the strip above the screen's visible frame, at least
    /// as tall as the status bar; the snapshot holds that height.
    private static func visibleMenuBarRect(on displayID: CGDirectDisplayID, click: CGPoint, state: Snapshot) -> CGRect? {
        let displayBounds = CGDisplayBounds(displayID)
        let height: CGFloat
        if state.isFullscreenSpace {
            // The window list costs a few milliseconds; a click far from the top edge cannot be a
            // click on the bar.
            guard click.y - displayBounds.minY < 200, let menuBarWindow = WindowInfo.menuBarWindow(for: displayID) else {
                return nil
            }
            height = menuBarWindow.bounds.height
        } else {
            guard let barHeight = state.barHeights[displayID] else {
                return nil
            }
            height = barHeight
        }
        return CGRect(x: displayBounds.minX, y: displayBounds.minY, width: displayBounds.width, height: height)
    }
}
