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

/// Draws the zones and handles of one `OverlayLayout`, in the panel's coordinates.
final class HandleView: NSView {
    var layout: OverlayLayout {
        didSet {
            needsDisplay = true
        }
    }

    init(layout: OverlayLayout) {
        self.layout = layout
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        drawZones()
        drawHandles()
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
        guard !closed else {
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
        guard !closed, let shown = snapshot else {
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
}
