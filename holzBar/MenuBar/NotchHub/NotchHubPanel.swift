//
//  NotchHubPanel.swift
//  holzBar
//

import AppKit

/// The borderless panel the Notch hub is drawn in, above the menu bar.
///
/// It is always dark: the hub continues the black of the hardware notch, in light mode too, so
/// the panel fixes its own appearance. It never activates holzBar. It takes the keyboard only
/// when the hotkey opened it, so that Esc and the arrow keys work there; a hub that hover
/// opened leaves the keyboard to the app in front, so a pointer that brushes the notch never
/// interrupts typing.
final class NotchHubPanel: NSPanel {
    /// Whether the panel takes keys: the hotkey opened it.
    var acceptsKeyboard = false

    /// Called when Esc is pressed in the panel.
    var onEscape: (() -> Void)?

    /// Creates the panel, hidden and without content.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        title = "Notch hub"
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .mainMenu + 2
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        hidesOnDeactivate = false
        // Without it a pointer that moves inside the hub is not reported, and the hub would
        // not know that the pointer is still there.
        acceptsMouseMovedEvents = true
        applyDarkAppearance()
    }

    override var canBecomeKey: Bool { acceptsKeyboard }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override var canBecomeMain: Bool { false }

    /// The hub lies over the menu bar and over the notch's strip, which AppKit would otherwise
    /// move below the bar: the frame is exactly what the geometry computed.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Fixes the dark appearance, in its high-contrast variant while Increase Contrast is on,
    /// so the colours of the theme resolve the way they do for any dark window.
    func applyDarkAppearance() {
        let name: NSAppearance.Name = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? .accessibilityHighContrastDarkAqua
            : .darkAqua
        appearance = NSAppearance(named: name)
    }
}
