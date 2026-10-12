//
//  CommandDragTap.swift
//  holzBar
//

import AppKit
import CoreGraphics
import MenuBarDragCore

/// What the probe measured for one drag that started on an app item.
struct GestureRecord: Sendable {
    /// The mechanism, `a1` or `a2`.
    let mechanism: String

    let dragged: BarItem

    /// Whether the press already held Command, which is the native baseline.
    let commandHeld: Bool

    /// The release point's x, in points.
    let dropX: CGFloat

    /// The bar as it was cached when the button went down.
    let before: BarSnapshot

    /// The first read after the drop, for the overlay measurements of the second spike plan.
    let firstSample: BarSnapshot?

    let result: SettleResult

    /// The longest callback of the tap so far, in microseconds.
    let tapMaxUs: Int
}

/// What the probe measured for one press that a2 held back and then replayed as a click or as
/// a press that tracks a menu.
struct ClickRecord: Sendable {
    /// What the press turned out to be.
    enum Kind: String, Sendable {
        /// The button went up where it went down: a plain click.
        case click

        /// The pointer left the bar downward: a press that tracks a menu.
        case menuDrag
    }

    let mechanism: String
    let item: BarItem

    /// How long the press was held back, in milliseconds.
    let replayDelayMs: Int

    let kind: Kind
}

/// An event tap that turns plain drags on app items into Command-drags and measures what the bar
/// does afterwards.
///
/// Only the three left-button event types are tapped, nothing else is read, and the tap exists
/// only while a1 or a2 runs. In rewrite mode (a1) it only changes the flags and the location of
/// the user's own events and never posts an event. In hold-and-decide mode (a2) it holds a press
/// back and posts marked replays, which it recognises by their marker. It writes no output:
/// records go to the callbacks.
final class CommandDragTap {
    /// What the tap does with a press on an app item.
    enum Mode {
        /// Adds Command to the user's own events of the drag (a1).
        case rewrite

        /// Holds a press on an app item back and decides what it was (a2).
        case holdAndDecide

        /// The mechanism's name in the report.
        var mechanism: String {
            switch self {
            case .rewrite: "a1"
            case .holdAndDecide: "a2"
            }
        }
    }

    /// Set on every event the tap posts, so the tap lets its own replays through.
    static let replayMarker: Int64 = 0x77D2A6

    /// The drag that is going on.
    private struct Gesture {
        let dragged: BarItem
        let before: BarSnapshot

        /// Whether the user's own press already held Command; such a gesture is left alone.
        let userHeldCommand: Bool
    }

    private let mode: Mode
    private let generation: Generation
    private let onGesture: (GestureRecord) -> Void
    private let onClick: (ClickRecord) -> Void
    private let onSkip: (String) -> Void
    private var decider = GestureDecider()
    private let source = CGEventSource(stateID: .hidSystemState)

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var observers = [any NSObjectProtocol]()
    private var workspaceObservers = [any NSObjectProtocol]()

    /// The bar as last read; the hit tests of the callback use it, never a live read.
    private(set) var snapshot: BarSnapshot
    private var barHeights = [UInt32: CGFloat]()
    private var gesture: Gesture?

    /// Whether the bounded reads of a previous drop are still running.
    private var measuring = false
    private var busyReported = false
    private var readsTask: Task<Void, Never>?

    /// The longest callback so far, in microseconds.
    private(set) var tapMaxUs = 0

    init(
        mode: Mode,
        generation: Generation,
        snapshot: BarSnapshot,
        onGesture: @escaping (GestureRecord) -> Void,
        onClick: @escaping (ClickRecord) -> Void,
        onSkip: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.generation = generation
        self.snapshot = snapshot
        self.onGesture = onGesture
        self.onClick = onClick
        self.onSkip = onSkip
    }

    /// The callback shared by the tap; it hands the event to the instance in the refcon.
    private static let sharedCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<CommandDragTap>.fromOpaque(refcon).takeUnretainedValue()
        let passes = tap.handle(type: type, event: event)
        return passes ? Unmanaged.passUnretained(event) : nil
    }

    /// Creates the tap and starts listening; `false` when macOS refuses the tap.
    func start() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard
            let port = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: Self.sharedCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ),
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        else {
            return false
        }
        machPort = port
        runLoopSource = source
        barHeights = BarReader.barHeights()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        observeChangesOfTheBar()
        return true
    }

    /// Takes the tap out of the event stream.
    func stop() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        machPort = nil
        runLoopSource = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        workspaceObservers.removeAll()
    }

    /// Waits until the reads after the last drop are done.
    func waitForReads() async {
        await readsTask?.value
    }

    // MARK: - The cached bar

    /// Reads the bar again when it can have changed: another display setup, an app that starts or
    /// quits. These are events, never a timer.
    private func observeChangesOfTheBar() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.barHeights = BarReader.barHeights()
                self?.refreshSnapshot()
            }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshSnapshot()
                }
            })
        }
    }

    /// Reads the bar off the main actor and caches it, unless a drag is going on.
    private func refreshSnapshot() {
        let heights = barHeights
        let generation = generation
        let pointer = CGEvent(source: nil)?.location
        Task {
            let fresh = await Task.detached(priority: .userInitiated) {
                BarReader.snapshot(near: pointer, barHeights: heights, generation: generation)
            }.value
            if gesture == nil, !measuring {
                snapshot = fresh
            }
        }
    }

    // MARK: - The callback

    /// Whether the event goes on (possibly changed) or is dropped.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            return false
        }
        let started = ContinuousClock.now
        let passes = decide(type: type, event: event)
        let elapsed = started.duration(to: .now).components
        let microseconds = Int(elapsed.seconds) * 1_000_000 + Int(elapsed.attoseconds / 1_000_000_000_000)
        tapMaxUs = max(tapMaxUs, microseconds)
        return passes
    }

    private func decide(type: CGEventType, event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return true
        }
        switch mode {
        case .rewrite:
            rewrite(type: type, event: event)
            return true
        case .holdAndDecide:
            return holdAndDecide(type: type, event: event)
        }
    }

    // MARK: - Rewrite mode (a1)

    private func rewrite(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown:
            gesture = nil
            guard let item = snapshot.item(at: event.location), item.kind == .app else {
                return
            }
            guard !measuring else {
                reportBusyOnce()
                return
            }
            let userHeldCommand = event.flags.contains(.maskCommand)
            gesture = Gesture(dragged: item, before: snapshot, userHeldCommand: userHeldCommand)
            if !userHeldCommand {
                event.flags.insert(.maskCommand)
            }
        case .leftMouseDragged:
            guard let gesture, !gesture.userHeldCommand else {
                return
            }
            addCommandInsideBar(event)
        case .leftMouseUp:
            guard let gesture else {
                return
            }
            if !gesture.userHeldCommand {
                addCommandInsideBar(event)
            }
            self.gesture = nil
            beginReads(for: gesture, dropX: event.location.x, releasePoint: event.location)
        default:
            break
        }
    }

    /// Adds Command and keeps the location inside the bar strip: a Command-drag that ends off the
    /// bar removes an item that allows removal.
    private func addCommandInsideBar(_ event: CGEvent) {
        event.flags.insert(.maskCommand)
        event.location = insideBar(event.location)
    }

    /// The point itself, or the nearest point inside the bar strip.
    private func insideBar(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: min(point.y, snapshot.barMaxY - 2))
    }

    private func reportBusyOnce() {
        guard !busyReported else {
            return
        }
        busyReported = true
        onSkip("busy")
    }

    // MARK: - Hold and decide mode (a2)

    /// Returns whether the event goes on; a press on an app item that is held back is dropped.
    private func holdAndDecide(type: CGEventType, event: CGEvent) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .leftMouseDown:
            gesture = nil
            guard let item = snapshot.item(at: event.location), item.kind == .app else {
                _ = decider.mouseDown(at: event.location, time: now, onItem: false)
                return true
            }
            guard !measuring else {
                _ = decider.mouseDown(at: event.location, time: now, onItem: false)
                reportBusyOnce()
                return true
            }
            if event.flags.contains(.maskCommand) {
                // The native baseline: a press that already holds Command passes unchanged.
                _ = decider.mouseDown(at: event.location, time: now, onItem: false)
                gesture = Gesture(dragged: item, before: snapshot, userHeldCommand: true)
                return true
            }
            gesture = Gesture(dragged: item, before: snapshot, userHeldCommand: false)
            return decider.mouseDown(at: event.location, time: now, onItem: true) == .pass
        case .leftMouseDragged:
            if let gesture, gesture.userHeldCommand {
                return true
            }
            return held(dragged: event, now: now)
        case .leftMouseUp:
            if let gesture, gesture.userHeldCommand {
                self.gesture = nil
                beginReads(for: gesture, dropX: event.location.x, releasePoint: event.location)
                return true
            }
            return held(up: event, now: now)
        default:
            return true
        }
    }

    private func held(dragged event: CGEvent, now: Double) -> Bool {
        let pressedAt = decider.heldSince
        switch decider.mouseDragged(to: event.location, time: now, barMaxY: snapshot.barMaxY) {
        case .pass:
            return true
        case .swallow:
            return false
        case .rewriteWithCommand:
            addCommandInsideBar(event)
            return true
        case .replayCommandDown(let down):
            post(.leftMouseDown, at: down, flags: event.flags.union(.maskCommand))
            post(.leftMouseDragged, at: insideBar(event.location), flags: event.flags.union(.maskCommand))
            return false
        case .replayPlainDown(let down):
            post(.leftMouseDown, at: down, flags: event.flags)
            post(.leftMouseDragged, at: event.location, flags: event.flags)
            if let gesture, let pressedAt {
                onClick(ClickRecord(
                    mechanism: mode.mechanism,
                    item: gesture.dragged,
                    replayDelayMs: Int(((now - pressedAt) * 1000).rounded()),
                    kind: .menuDrag
                ))
            }
            gesture = nil
            return false
        case .replayClick:
            return true
        }
    }

    private func held(up event: CGEvent, now: Double) -> Bool {
        let pressedAt = decider.heldSince
        let finished = gesture
        switch decider.mouseUp(at: event.location, time: now) {
        case .replayClick(let down, let up):
            post(.leftMouseDown, at: down, flags: event.flags)
            post(.leftMouseUp, at: up, flags: event.flags)
            if let finished, let pressedAt {
                onClick(ClickRecord(
                    mechanism: mode.mechanism,
                    item: finished.dragged,
                    replayDelayMs: Int(((now - pressedAt) * 1000).rounded()),
                    kind: .click
                ))
            }
            gesture = nil
            return false
        case .rewriteWithCommand:
            addCommandInsideBar(event)
            gesture = nil
            if let finished {
                beginReads(for: finished, dropX: event.location.x, releasePoint: event.location)
            }
            return true
        default:
            gesture = nil
            return true
        }
    }

    /// Posts a marked left-button event, so the tap lets it through and the replay is told apart
    /// from the user's own events.
    private func post(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags) {
        guard let event = CGEvent(
            mouseEventSource: source,
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

    // MARK: - The bounded reads after a drop

    /// Reads the bar at `SettleSeries.offsetsMs` after the release, then evaluates the series.
    /// Nothing is read before the next drop.
    private func beginReads(for gesture: Gesture, dropX: CGFloat, releasePoint: CGPoint) {
        measuring = true
        let release = ContinuousClock.now
        let heights = barHeights
        let generation = generation
        readsTask = Task {
            var samples = [SettleSeries.Sample]()
            for offset in SettleSeries.offsetsMs {
                do {
                    try await Task.sleep(until: release.advanced(by: .milliseconds(offset)), clock: .continuous)
                } catch {
                    break
                }
                let read = await Task.detached(priority: .userInitiated) {
                    BarReader.snapshot(near: releasePoint, barHeights: heights, generation: generation)
                }.value
                samples.append(SettleSeries.Sample(offsetMs: offset, snapshot: read))
            }
            finishReads(for: gesture, dropX: dropX, samples: samples)
        }
    }

    private func finishReads(for gesture: Gesture, dropX: CGFloat, samples: [SettleSeries.Sample]) {
        let result = SettleSeries.evaluate(before: gesture.before, draggedID: gesture.dragged.id, samples: samples)
        if let last = samples.last {
            snapshot = last.snapshot
        }
        measuring = false
        busyReported = false
        onGesture(GestureRecord(
            mechanism: mode.mechanism,
            dragged: gesture.dragged,
            commandHeld: gesture.userHeldCommand,
            dropX: dropX,
            before: gesture.before,
            firstSample: samples.first?.snapshot,
            result: result,
            tapMaxUs: tapMaxUs
        ))
    }
}
