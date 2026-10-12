//
//  HandleOverlay.swift
//  holzBar
//

import AppKit
import MenuBarDragCore

// Mechanism B of the Phase 77 spike (Preview, throwaway, not part of holzBar.app): holzBar's own
// panel over the menu bar of one display, with a drag handle over every counted item and two drop
// zones, Hidden and Always Hidden.
//
// The panel exists only while `b` runs. It reads no input outside its own panel: mouse events on
// its handles and Escape while it is the key window, nothing else. It follows the bar through
// notifications only (screen parameters, Space, app activation, launch and quit), never a timer.

/// The borderless panel over the bar. It becomes key without activating the probe, so Escape
/// reaches it.
final class HandlePanel: NSPanel {
    /// Called when Escape is pressed while the panel is the key window.
    var onEscape: () -> Void = {}

    override var canBecomeKey: Bool { true }

    init(windowLevel: Int) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: windowLevel)
        // Not on all Spaces: the panel stays on the Space where `b` started, so a full-screen
        // app's Space shows no handles.
        collectionBehavior = [.ignoresCycle, .fullScreenNone]
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// What the view shows of a drag that is going on.
struct DragFeedback {
    /// Where a drop would land.
    enum Indicator {
        /// A vertical line at x, between two items.
        case line(x: CGFloat)

        /// Rects to highlight: a zone, or holzBar's icon on macOS 27.
        case highlight([CGRect])
    }

    /// The dragged handle, moved to the pointer.
    let draggedRect: CGRect
    let indicator: Indicator?
}

/// Draws the zones and handles of one `OverlayLayout`, in the panel's coordinates, and hands the
/// mouse events on them to the overlay.
final class HandleView: NSView {
    var layout: OverlayLayout {
        didSet {
            needsDisplay = true
        }
    }

    var feedback: DragFeedback? {
        didSet {
            needsDisplay = true
        }
    }

    weak var overlay: HandleOverlay?

    init(layout: OverlayLayout) {
        self.layout = layout
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        overlay?.mouseDown(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        overlay?.mouseDragged(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        overlay?.mouseUp(at: convert(event.locationInWindow, from: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        drawZones()
        drawHandles()
        drawFeedback()
        if let first = layout.zones.first, first.rect.minX >= 200 {
            drawLabel("holzBar drag spike (Preview)", at: NSPoint(x: 6, y: (bounds.height - 14) / 2))
        }
    }

    private func drawZones() {
        for zone in layout.zones {
            let path = NSBezierPath(roundedRect: zone.rect, xRadius: 4, yRadius: 4)
            NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
            path.fill()
            let text = zone.section == .hidden ? "Hidden" : "Always Hidden"
            let attributes = Self.labelAttributes
            let size = (text as NSString).size(withAttributes: attributes)
            let origin = NSPoint(x: zone.rect.midX - size.width / 2, y: zone.rect.midY - size.height / 2)
            (text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }

    private func drawHandles() {
        for handle in layout.handles {
            let rect = handle.rect.insetBy(dx: 1, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            switch handle.kind {
            case .app:
                NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
                path.fill()
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 1.5
            case .system:
                NSColor.secondaryLabelColor.setStroke()
                path.lineWidth = 1
                path.setLineDash([3, 2], count: 2, phase: 0)
            case .holzBarIcon, .hiddenDivider, .alwaysHiddenDivider, .holzBarOther:
                NSColor.systemOrange.setStroke()
                path.lineWidth = 1.5
            }
            path.stroke()
        }
    }

    private func drawFeedback() {
        guard let feedback else {
            return
        }
        switch feedback.indicator {
        case .line(let x):
            NSColor.controlAccentColor.setFill()
            NSRect(x: x - 1, y: 2, width: 2, height: max(0, bounds.height - 4)).fill()
        case .highlight(let rects):
            for rect in rects {
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                NSColor.controlAccentColor.withAlphaComponent(0.5).setFill()
                path.fill()
            }
        case nil:
            break
        }
        let dragged = NSBezierPath(roundedRect: feedback.draggedRect.insetBy(dx: 1, dy: 2), xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.5).setFill()
        dragged.fill()
    }

    private static var labelAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private func drawLabel(_ text: String, at point: NSPoint) {
        (text as NSString).draw(at: point, withAttributes: Self.labelAttributes)
    }
}

/// The overlay of `b`: the panel, what it shows and how it follows the bar.
final class HandleOverlay {
    private let level: Int
    private let generation: Generation
    private let session: Session
    private let panel: HandlePanel

    /// The bar as the overlay shows it.
    private(set) var snapshot: BarSnapshot?
    private var layout: OverlayLayout?
    private var view: HandleView?

    private var observers = [any NSObjectProtocol]()
    private var workspaceObservers = [any NSObjectProtocol]()
    private var followUps = [Task<Void, Never>]()
    private var closed = false

    /// The drag that is going on.
    private struct Drag {
        let item: BarItem
        let before: BarSnapshot
        let handleRect: CGRect
    }

    private var drag: Drag?

    /// Whether a drop is being executed and measured; nothing else is taken meanwhile.
    private var measuring = false
    private var busyReported = false
    private var readsTask: Task<Void, Never>?

    init(level: Int, generation: Generation, session: Session) {
        self.level = level
        self.generation = generation
        self.session = session
        panel = HandlePanel(windowLevel: level)
        panel.onEscape = {
            Task {
                await session.finishAfterReads()
            }
        }
    }

    /// The primary display's height and the span of the notch on the snapshot's display, taken
    /// from the screens as they are now.
    static func screenGeometry(for snapshot: BarSnapshot) -> (primaryHeight: CGFloat, notchSpan: ClosedRange<CGFloat>?) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? snapshot.displayBounds.height
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == snapshot.displayID
        }
        guard
            let screen, screen.safeAreaInsets.top > 0,
            let left = screen.auxiliaryTopLeftArea?.width,
            let right = screen.auxiliaryTopRightArea?.width
        else {
            return (primaryHeight, nil)
        }
        let lower = snapshot.displayBounds.minX + left
        let upper = snapshot.displayBounds.maxX - right
        return (primaryHeight, lower < upper ? lower...upper : nil)
    }

    /// Builds the layout, shows the panel and starts following the bar. The session writes the
    /// OVERLAY line once the first display is done.
    func show(snapshot: BarSnapshot, primaryDisplayHeight: CGFloat, notchSpan: ClosedRange<CGFloat>?) {
        let layout = OverlayLayout.make(
            snapshot: snapshot,
            primaryDisplayHeight: primaryDisplayHeight,
            notchSpan: notchSpan
        )
        self.snapshot = snapshot
        self.layout = layout
        let view = HandleView(layout: layout)
        view.overlay = self
        self.view = view
        panel.contentView = view
        panel.setFrame(layout.panelFrame, display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.displayIfNeeded()
        session.recordOverlay(
            level: level,
            handles: layout.handles.count,
            zones: layout.zones.count,
            display: snapshot.displayID
        )
        observeChangesOfTheBar()
    }

    /// Takes the panel off the screen and removes every observer.
    func close() {
        closed = true
        for task in followUps {
            task.cancel()
        }
        followUps.removeAll()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        workspaceObservers.removeAll()
        panel.orderOut(nil)
    }

    // MARK: - Following the bar

    /// Notifications only: screen parameters, Space, app activation, launch and quit. After a
    /// launch or a quit the bar is read twice more, because an item appears or goes a moment after
    /// its app.
    private func observeChangesOfTheBar() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.track(event: "screens")
            }
        })
        let events: [(Notification.Name, String, Bool)] = [
            (NSWorkspace.activeSpaceDidChangeNotification, "space", false),
            (NSWorkspace.didActivateApplicationNotification, "activate", false),
            (NSWorkspace.didLaunchApplicationNotification, "launch", true),
            (NSWorkspace.didTerminateApplicationNotification, "terminate", true),
        ]
        for (name, event, followUp) in events {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.track(event: event)
                    if followUp {
                        self?.trackAgain(event: event)
                    }
                }
            })
        }
    }

    private func trackAgain(event: String) {
        for delay in [250, 1000] {
            followUps.append(Task {
                try? await Task.sleep(for: .milliseconds(delay))
                if !Task.isCancelled {
                    track(event: "\(event)+\(delay)")
                }
            })
        }
    }

    /// Reads the bar off the main actor, compares it with what the overlay shows, moves and
    /// redraws the panel, and has the session write the TRACK line.
    private func track(event: String) {
        guard !closed, !measuring, drag == nil else {
            return
        }
        let started = ContinuousClock.now
        let heights = BarReader.barHeights()
        let pointer = CGEvent(source: nil)?.location
        let generation = generation
        Task {
            let fresh = await Task.detached(priority: .userInitiated) {
                BarReader.snapshot(near: pointer, barHeights: heights, generation: generation)
            }.value
            apply(fresh, event: event, started: started)
        }
    }

    private func apply(_ fresh: BarSnapshot, event: String, started: ContinuousClock.Instant) {
        guard !closed, !measuring, drag == nil, let shown = snapshot else {
            return
        }
        let diff = TrackDiff.compare(shown: shown, fresh: fresh)
        redraw(with: fresh)
        let elapsed = started.duration(to: .now)
        session.recordTrack(
            event: event,
            items: fresh.orderedIDs().count,
            shifted: diff.shifted,
            maxShift: diff.maxShift,
            redrawMs: elapsed.wholeMilliseconds
        )
    }

    /// Builds the layout again from `fresh`, with the primary height and the notch span taken from
    /// the screens as they are now, and moves the panel.
    private func redraw(with fresh: BarSnapshot) {
        let geometry = Self.screenGeometry(for: fresh)
        let layout = OverlayLayout.make(
            snapshot: fresh,
            primaryDisplayHeight: geometry.primaryHeight,
            notchSpan: geometry.notchSpan
        )
        snapshot = fresh
        self.layout = layout
        panel.setFrame(layout.panelFrame, display: false)
        view?.layout = layout
        panel.displayIfNeeded()
    }

    /// Waits until the reads after the last drop are done.
    func waitForReads() async {
        await readsTask?.value
    }
}

// MARK: - Dragging a handle

extension HandleOverlay {
    /// How the events of a posted Command-drag are paced.
    private struct Pace {
        /// How long the pointer rests on the item, with Command, before the press (0: no rest).
        let restMs: Int

        /// How long the press is held before the pointer moves.
        let holdMs: Int
        let steps: Int
        let stepMs: Int

        /// How long the pointer rests at the destination before the release.
        let releaseMs: Int

        /// The pace of holzBar's own move before macOS 27 in the field: a short drag.
        static let fast = Pace(restMs: 0, holdMs: 0, steps: 10, stepMs: 10, releaseMs: 50)

        /// The pace of `Scripts/macos27/reorder-probe.swift`, which macOS 27 accepted.
        static let slow = Pace(restMs: 200, holdMs: 300, steps: 30, stepMs: 20, releaseMs: 300)
    }

    /// What is done with a resolved drop.
    private enum Plan {
        case post(from: CGPoint, to: CGPoint)
        case intentOnly
        case nothing
    }

    // MARK: Mouse

    func mouseDown(at point: CGPoint) {
        guard !closed, let layout, let snapshot else {
            return
        }
        guard !measuring else {
            NSSound.beep()
            if !busyReported {
                busyReported = true
                session.recordSkip("busy")
            }
            return
        }
        guard
            let handle = layout.handles.first(where: { $0.kind == .app && $0.rect.contains(point) }),
            let item = snapshot.item(withID: handle.id)
        else {
            NSSound.beep()
            return
        }
        drag = Drag(item: item, before: snapshot, handleRect: handle.rect)
    }

    func mouseDragged(to point: CGPoint) {
        guard let drag, let layout else {
            return
        }
        let target = resolve(point, drag: drag, layout: layout)
        var rect = drag.handleRect
        rect.origin.x = point.x - rect.width / 2
        view?.feedback = DragFeedback(
            draggedRect: rect,
            indicator: indicator(for: target, at: layout.cgPoint(fromPanel: point), layout: layout)
        )
    }

    func mouseUp(at point: CGPoint) {
        view?.feedback = nil
        guard let finished = drag, let layout else {
            return
        }
        drag = nil
        let target = resolve(point, drag: finished, layout: layout)
        let releaseX = layout.cgPoint(fromPanel: point).x
        measuring = true
        readsTask = Task {
            await perform(finished, target: target, releaseX: releaseX)
        }
    }

    private func resolve(_ point: CGPoint, drag: Drag, layout: OverlayLayout) -> DropTarget? {
        DropResolver.target(
            forDropAt: layout.cgPoint(fromPanel: point),
            draggedID: drag.item.id,
            in: drag.before,
            zones: layout.zones.map(\.dropZone)
        )
    }

    private func indicator(for target: DropTarget?, at point: CGPoint, layout: OverlayLayout) -> DragFeedback.Indicator? {
        guard let target else {
            return nil
        }
        switch target {
        case .leftOf(let id):
            return layout.handles.first { $0.id == id }.map { .line(x: $0.rect.minX) }
        case .rightOf(let id):
            return layout.handles.first { $0.id == id }.map { .line(x: $0.rect.maxX) }
        case .section:
            if let zone = layout.zones.first(where: { $0.dropZone.frame.contains(point) }) {
                return .highlight([zone.rect])
            }
            return layout.handles.first { $0.kind == .holzBarIcon }.map { .highlight([$0.rect]) }
        }
    }

    // MARK: Executing a drop

    /// Resolves the drop into an intent, executes it as holzBar's own move would, reads the bar
    /// after it as A does, and hands the record to the session.
    private func perform(_ drag: Drag, target: DropTarget?, releaseX: CGFloat) async {
        let before = drag.before
        let item = drag.item
        let currentSection = generation == .before27 ? before.positionalSection(of: item) : nil
        let intent = DropResolver.intent(for: target, dragged: item, in: before, currentSection: currentSection)

        var samples = [SettleSeries.Sample]()
        var executed = "none"
        var retried: Bool?
        switch plan(for: intent, target: target, item: item, in: before) {
        case .nothing:
            break
        case .intentOnly:
            // holzBar's saved layout is not the probe's to set; the reads show the bar stayed.
            executed = "intent-only"
            samples = await readSeries(after: .now, near: Self.centre(of: item, in: before))
        case .post(let start, let end):
            executed = "posted-fast"
            retried = false
            panel.ignoresMouseEvents = true
            var release = await postCommandDrag(from: start, to: end, pace: .fast)
            samples = await readSeries(after: release, near: end)
            if
                let target, let latest = samples.last?.snapshot,
                DropResolver.landed(target, draggedID: item.id, in: latest) == false,
                let moved = latest.item(withID: item.id),
                let retryEnd = destination(for: target, in: latest)
            {
                executed = "posted-slow"
                retried = true
                release = await postCommandDrag(from: Self.centre(of: moved, in: latest), to: retryEnd, pace: .slow)
                samples = await readSeries(after: release, near: retryEnd)
            }
            panel.ignoresMouseEvents = false
        }

        let result = SettleSeries.evaluate(before: before, draggedID: item.id, samples: samples)
        var landed: Bool?
        if let target, let final = samples.last?.snapshot {
            landed = DropResolver.landed(target, draggedID: item.id, in: final)
        }
        if !closed {
            redraw(with: samples.last?.snapshot ?? before)
        }
        measuring = false
        busyReported = false
        session.record(GestureRecord(
            mechanism: "b",
            dragged: item,
            commandHeld: false,
            dropX: releaseX,
            before: before,
            firstSample: samples.first?.snapshot,
            result: result,
            intent: intent,
            landed: landed,
            executed: executed,
            retried: retried,
            tapMaxUs: nil
        ))
    }

    private func plan(for intent: DropIntent, target: DropTarget?, item: BarItem, in bar: BarSnapshot) -> Plan {
        let start = Self.centre(of: item, in: bar)
        switch intent {
        case .refused:
            return .nothing
        case .setSection:
            guard generation == .before27 else {
                return .intentOnly
            }
            guard let target, let end = destination(for: target, in: bar) else {
                return .nothing
            }
            return .post(from: start, to: end)
        case .move(_, let moveTarget):
            return destination(for: moveTarget, in: bar).map { .post(from: start, to: $0) } ?? .nothing
        case .macOSOrders:
            guard let target, let end = destination(for: target, in: bar) else {
                return .nothing
            }
            return .post(from: start, to: end)
        }
    }

    /// The centre of an item, with y kept inside the bar.
    private static func centre(of item: BarItem, in bar: BarSnapshot) -> CGPoint {
        CGPoint(x: item.frame.midX, y: min(item.frame.midY, bar.barMaxY - 2))
    }

    /// Where a Command-drag is released for a target: just inside the neighbour's near edge, or,
    /// before macOS 27, at the left edge of the section's divider. y stays inside the bar so no
    /// release lands off it.
    private func destination(for target: DropTarget, in bar: BarSnapshot) -> CGPoint? {
        func y(_ item: BarItem) -> CGFloat {
            min(item.frame.midY, bar.barMaxY - 2)
        }
        switch target {
        case .leftOf(let id):
            return bar.item(withID: id).map { CGPoint(x: $0.frame.minX + 2, y: y($0)) }
        case .rightOf(let id):
            return bar.item(withID: id).map { CGPoint(x: $0.frame.maxX - 2, y: y($0)) }
        case .section(let section):
            guard bar.generation == .before27 else {
                return nil
            }
            let kind: BarItem.Kind
            switch section {
            case .hidden: kind = .hiddenDivider
            case .alwaysHidden: kind = .alwaysHiddenDivider
            case .visible: return nil
            }
            guard let divider = bar.items.first(where: { $0.kind == kind && $0.counts }) else {
                return nil
            }
            return CGPoint(x: max(divider.frame.minX + 2, bar.displayBounds.minX + 2), y: y(divider))
        }
    }

    // MARK: Posting

    /// Posts a Command mouse-down at `start`, dragged events towards `end` and a Command mouse-up
    /// at `end`, as holzBar's backend moves an item before macOS 27, and puts the cursor back.
    /// Every event carries the replay marker. Returns the instant of the release.
    private func postCommandDrag(from start: CGPoint, to end: CGPoint, pace: Pace) async -> ContinuousClock.Instant {
        let cursor = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        if pace.restMs > 0 {
            post(.mouseMoved, at: start, source: source)
            try? await Task.sleep(for: .milliseconds(pace.restMs))
        }
        post(.leftMouseDown, at: start, source: source)
        if pace.holdMs > 0 {
            try? await Task.sleep(for: .milliseconds(pace.holdMs))
        }
        for step in 1...pace.steps {
            try? await Task.sleep(for: .milliseconds(pace.stepMs))
            let fraction = CGFloat(step) / CGFloat(pace.steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction)
            post(.leftMouseDragged, at: point, source: source)
        }
        try? await Task.sleep(for: .milliseconds(pace.releaseMs))
        post(.leftMouseUp, at: end, source: source)
        let release = ContinuousClock.now
        if let cursor {
            CGWarpMouseCursorPosition(cursor)
        }
        CGAssociateMouseAndMouseCursorPosition(1)
        return release
    }

    private func post(_ type: CGEventType, at point: CGPoint, source: CGEventSource?) {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return
        }
        event.flags = .maskCommand
        event.setIntegerValueField(.eventSourceUserData, value: CommandDragTap.replayMarker)
        if type != .leftMouseDragged, type != .mouseMoved {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }

    // MARK: Reading

    /// Reads the bar at `SettleSeries.offsetsMs` after `release`, as A does. Nothing is read
    /// before the next drop.
    private func readSeries(after release: ContinuousClock.Instant, near point: CGPoint) async -> [SettleSeries.Sample] {
        let heights = BarReader.barHeights()
        let generation = generation
        var samples = [SettleSeries.Sample]()
        for offset in SettleSeries.offsetsMs {
            do {
                try await Task.sleep(until: release.advanced(by: .milliseconds(offset)), clock: .continuous)
            } catch {
                break
            }
            let read = await Task.detached(priority: .userInitiated) {
                BarReader.snapshot(near: point, barHeights: heights, generation: generation)
            }.value
            samples.append(SettleSeries.Sample(offsetMs: offset, snapshot: read))
        }
        return samples
    }
}
