//
//  CaptureDotView.swift
//  holzBar
//

import Cocoa

/// The dot holzBar draws over its own icon while another app records on macOS 27.
///
/// A subview rather than part of the image, so the icon keeps its template rendering and the
/// dot its colour. The colour resolves for the current appearance when the layer updates.
final class CaptureDotView: NSView {
    /// The dot's diameter, in points.
    static let diameter: CGFloat = 6

    /// The dot's colour.
    var color: NSColor = .systemOrange {
        didSet {
            needsDisplay = true
        }
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        wantsLayer = true
        // The button carries the description; the dot is decoration.
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = bounds.width / 2
    }

    /// Lets a click on the dot reach holzBar's button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
