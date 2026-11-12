//
//  UndoToastPanel.swift
//  holzBar
//

import AppKit
import SwiftUI

/// Shows the undo toast of a change made at the menu bar, under the holzBar icon, without
/// bringing holzBar or Settings to the front (D-14).
///
/// The panel never becomes key and never activates holzBar; its first click acts at once, so
/// Undo works while another app is in front. It is made at the first such toast and only
/// ordered out afterwards (D-33).
final class UndoToastPanel: NSPanel {
    private let hostingView: UndoToastHostingView

    override var canBecomeKey: Bool { false }

    init(undo: LayoutUndo) {
        hostingView = UndoToastHostingView(rootView: UndoToastView(undo: undo, place: .menuBar))
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )
        self.title = String(localized: "Undo")
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .none
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        self.contentView = hostingView
    }

    /// Shows the toast under the holzBar icon, or at the trailing edge of the active menu bar's
    /// screen when the icon has no frame.
    func show(for appState: AppState) {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else {
            return
        }
        let controlItem = appState.menuBarManager.controlItem(withName: .visible)
        let iconFrame = controlItem?.frame
        guard let screen = controlItem?.screen ?? NSScreen.screenWithActiveMenuBar ?? NSScreen.main else {
            return
        }
        let visible = screen.visibleFrame
        let margin = HolzBarTheme.UndoToast.screenMargin
        let centre = iconFrame?.midX ?? (visible.maxX - margin - size.width / 2)
        let x = min(max(centre - size.width / 2, visible.minX + margin), visible.maxX - margin - size.width)
        let y = visible.maxY - HolzBarTheme.UndoToast.menuBarGap - size.height
        setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }

    /// Takes the toast away.
    func hide() {
        orderOut(nil)
    }
}

/// Hosts the toast in a view that takes the first click, as the What's New window does.
private final class UndoToastHostingView: NSHostingView<UndoToastView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
