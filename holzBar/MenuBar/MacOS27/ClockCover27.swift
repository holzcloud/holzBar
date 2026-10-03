//
//  ClockCover27.swift
//  holzBar
//

import Cocoa

/// Covers the part of the bar where concealed items appear while a click on the clock lifts
/// concealment on macOS 27.
///
/// A click on the clock reaches MenuBarAgent only while no assertion stands, so the bridge
/// lifts concealment for a moment, and every hidden item flashed into view for it (Thaw
/// #1181). The cover stands over that part of the bar — from the end of the application
/// menus, or the notch, to the first item drawn while concealed — and shows the desktop
/// picture there, as the bar does, with the menu bar's tint. It takes no screenshot.
@available(macOS 27.0, *)
@MainActor
final class ClockCover27 {
    /// The panel, created on first use.
    private var panel: NSPanel?

    /// Takes the cover away after the replayed click.
    private var hideTask: Task<Void, Never>?

    /// Puts the cover over the concealed part of the active bar. Does nothing when that part
    /// cannot be told.
    func show(appState: AppState) {
        hideTask?.cancel()
        hideTask = nil
        guard
            let screen = NSScreen.screenWithActiveMenuBar,
            let leftEdge = MenuBarItemProvider27.leftEdge(for: screen.displayID),
            let menuBarHeight = screen.getMenuBarHeight()
        else {
            return
        }
        let displayBounds = CGDisplayBounds(screen.displayID)
        var startX = displayBounds.minX
        if let applicationMenuFrame = appState.applicationMenuFrames.frame(for: screen) {
            startX = max(startX, applicationMenuFrame.maxX)
        }
        if let notch = screen.frameOfNotch, notch.maxX < leftEdge {
            startX = max(startX, notch.maxX)
        }
        guard leftEdge - startX > 1 else {
            return
        }
        let frame = CGRect(
            x: startX,
            y: screen.frame.maxY - menuBarHeight,
            width: leftEdge - startX,
            height: menuBarHeight
        )
        let panel = panel ?? makePanel()
        self.panel = panel
        let view = panel.contentView as? CoverView
        view?.strip = DesktopPicture.cachedStrip(for: screen, height: menuBarHeight)
        view?.stripOriginX = screen.frame.minX - startX
        view?.stripWidth = screen.frame.width
        view?.tint = Self.tint(appState: appState)
        view?.needsDisplay = true
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        // The next cover finds the picture ready.
        Task {
            _ = await DesktopPicture.strip(for: screen, height: menuBarHeight)
        }
    }

    /// Takes the cover away after the given delay.
    func hide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            self?.panel?.orderOut(nil)
        }
    }

    /// The tint of a custom menu bar appearance, drawn over the picture as the overlay does.
    private static func tint(appState: AppState) -> CGColor? {
        let configuration = appState.appearanceManager.configuration.current
        guard configuration.tintKind == .solid else {
            return nil
        }
        return configuration.tintColor.copy(alpha: 0.2)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the items MenuBarAgent draws at the status bar's level.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = CoverView()
        return panel
    }
}

// MARK: - CoverView

@available(macOS 27.0, *)
private final class CoverView: NSView {
    /// The desktop picture under the whole bar, or `nil` for the flat colour.
    var strip: CGImage?

    /// Where the strip starts, relative to the view's left edge.
    var stripOriginX: CGFloat = 0

    /// The strip's width: the screen's.
    var stripWidth: CGFloat = 0

    /// The tint over the picture.
    var tint: CGColor?

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        if let strip {
            context.draw(strip, in: CGRect(x: stripOriginX, y: 0, width: stripWidth, height: bounds.height))
        } else {
            context.setFillColor(HolzBarShelfColorManager.flatColor27())
            context.fill(bounds)
        }
        if let tint {
            context.setFillColor(tint)
            context.fill(bounds)
        }
    }
}
