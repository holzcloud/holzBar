//
//  CountBadgeView.swift
//  holzBar
//

import AppKit

/// The capsule with the number of hidden items that holzBar draws over its own icon.
///
/// A subview rather than part of the image, so the icon keeps its template rendering. Its colours
/// are the system's label pair (the capsule in the label colour, the number in the window
/// background colour), so it reads as part of the menu bar and has no colour of its own; both
/// resolve for the view's appearance each time it draws.
final class CountBadgeView: NSView {
    /// The capsule's height, in points.
    static let height: CGFloat = 11

    /// The space left and right of the number, in points.
    static let horizontalPadding: CGFloat = 3

    /// The number's font: monospaced digits, so the width does not jitter as the count changes.
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)

    /// The text on the badge.
    var text = "" {
        didSet {
            needsDisplay = true
        }
    }

    /// The width the badge needs for the given text, never narrower than it is high.
    static func width(for text: String) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return max(height, ceil(textWidth) + horizontalPadding * 2)
    }

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: Self.height, height: Self.height))
        wantsLayer = true
        // The button carries the description; the badge is decoration.
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        // AppKit draws with the view's effective appearance, so the system colours resolve for
        // the bar's light or dark look here, and again when the appearance changes.
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.windowBackgroundColor,
            .paragraphStyle: paragraph,
        ]
        let textHeight = (text as NSString).size(withAttributes: attributes).height
        let textRect = CGRect(
            x: bounds.minX,
            y: bounds.midY - textHeight / 2,
            width: bounds.width,
            height: textHeight
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Lets a click on the badge reach holzBar's button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}
