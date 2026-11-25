//
//  CountBadgeView.swift
//  holzBar
//

import AppKit

/// The capsule with the number of hidden items that holzBar draws over its own icon.
///
/// A subview rather than part of the image, so the icon keeps its template rendering. In the
/// default style its colours are the system's label pair (the capsule in the label colour, the
/// number in the window background colour), so it reads as part of the menu bar and has no colour
/// of its own; both resolve for the view's appearance each time it draws. The Dock badge item
/// uses the same shape in the Dock's red (``Style/dockBadge``).
final class CountBadgeView: NSView {
    /// How the capsule is coloured. The shape, height, padding and font are the same in both.
    enum Style {
        /// The system's label colour with the window background colour as text: holzBar's own
        /// count of hidden items.
        case label
        /// The Dock's red with white text, the same in both appearances: another app's badge
        /// shown as a Dock badge item (concept B1).
        case dockBadge
    }

    /// The red of ``Style/dockBadge``, from the design tokens.
    private static let dockBadgeFill = NSColor(
        srgbRed: DesignTokens.DockBadge.fill.red,
        green: DesignTokens.DockBadge.fill.green,
        blue: DesignTokens.DockBadge.fill.blue,
        alpha: 1
    )

    /// The capsule's height, in points.
    static let height: CGFloat = 11

    /// The space left and right of the number, in points.
    static let horizontalPadding: CGFloat = 3

    /// The number's font: monospaced digits, so the width does not jitter as the count changes.
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)

    /// How the capsule is coloured.
    private let style: Style

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

    init(style: Style = .label) {
        self.style = style
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
        let fill: NSColor
        let textColor: NSColor
        switch style {
        case .label:
            fill = .labelColor
            textColor = .windowBackgroundColor
        case .dockBadge:
            fill = Self.dockBadgeFill
            textColor = .white
        }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        // A text wider than the capsule is cut, never wrapped to a second line.
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: textColor,
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
