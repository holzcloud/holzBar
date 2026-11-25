//
//  LargePercentWidget.swift
//  holzBar
//

import AppKit

/// What only the Battery widget's Large Percent format draws (D-16).
///
/// The menu bar shows a small battery glyph, a gap and the percentage in the menu bar font plus
/// 3 pt, semibold, with digits of one width. The glyph sits in a slot as wide as the widest glyph
/// the widget can draw and the item has one width for the widest number, so neither a charge from
/// 9 to 100 percent nor a charger ever moves it. Everything is a template the system tints. The
/// glyph is decoration: VoiceOver and the tooltip say the battery speech of every battery widget.
enum LargePercentWidget {
    /// Whether the widget is a Battery text widget in the Large Percent format.
    static func isWidget(_ definition: WidgetDefinition) -> Bool {
        definition.kind == .text && definition.source == .battery && definition.preset == .largePercent
    }

    /// The widget draws its glyph in its title, so the button has no image of its own.
    static func configure(_ button: NSStatusBarButton) {
        button.image = nil
        button.imagePosition = .noImage
    }

    /// The font of the number: the widget font, larger and semibold, with digits of one width.
    static func numberFont(for font: NSFont) -> NSFont {
        numberFont(pointSize: font.pointSize)
    }

    /// The title: the glyph in its slot (while `showsGlyph`), the gap and the number. The glyph
    /// follows the charge and the charging state of the reading; without one it is the empty
    /// battery.
    static func title(
        for text: WidgetText,
        reading: WidgetReading,
        font: NSFont,
        showsGlyph: Bool
    ) -> NSAttributedString {
        let number = numberFont(for: font)
        let title = NSMutableAttributedString()
        if showsGlyph {
            let charge = charge(of: reading)
            let pointSize = glyphPointSize(menuFontSize: font.pointSize)
            let slot = slotSize(pointSize: pointSize)
            let attachment = NSTextAttachment()
            attachment.image = drawnSlot(
                symbol: BatteryGlyph.symbolName(percent: charge.percent, isCharging: charge.isCharging),
                pointSize: pointSize,
                size: slot
            )
            // The slot's middle sits on the middle of the number's capitals.
            attachment.bounds = CGRect(
                x: 0,
                y: (number.capHeight - slot.height) / 2,
                width: slot.width,
                height: slot.height
            )
            title.append(NSAttributedString(attachment: attachment))
            title.addAttribute(
                .kern,
                value: DesignTokens.Widget.largePercentGap,
                range: NSRange(location: 0, length: title.length)
            )
        }
        title.append(NSAttributedString(string: text.string, attributes: [.font: number]))
        return title
    }

    /// The one length of the item: the widest number (100 percent in the locale, or the en dash)
    /// with the widest glyph slot and the gap while the glyph shows, and the padding, rounded
    /// up. Measured with the item, never on a refresh.
    static func length(
        for definition: WidgetDefinition,
        font: NSFont,
        locale: Locale,
        padding: CGFloat
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: numberFont(for: font)]
        let samples = WidgetFormat.widthSamples(
            for: definition, locale: locale, calendar: .autoupdatingCurrent, capacityBytes: nil
        ) + [WidgetFormat.unavailable]
        let numberWidth = samples
            .map { NSAttributedString(string: $0, attributes: attributes).size().width }
            .max() ?? 0
        var glyphWidth = CGFloat.zero
        if definition.showsSymbol {
            glyphWidth = slotSize(pointSize: glyphPointSize(menuFontSize: font.pointSize)).width
                + DesignTokens.Widget.largePercentGap
        }
        return (numberWidth + glyphWidth + padding).rounded(.up)
    }

    /// The widget as an image of its own, for the Shelf and the layout editor: the same glyph and
    /// number as the menu bar, as a template at the height of a menu bar item. It takes plain
    /// values only: the image's drawing block runs whenever and wherever the image is drawn, so
    /// it holds nothing of the main actor.
    nonisolated static func picture(
        text: WidgetText,
        reading: WidgetReading,
        showsGlyph: Bool,
        fontSize: CGFloat,
        height: CGFloat
    ) -> NSImage? {
        let number = numberFont(pointSize: fontSize)
        let numberText = NSAttributedString(
            string: text.string,
            attributes: [.font: number, .foregroundColor: NSColor.black]
        )
        let textSize = numberText.size()
        let glyphSize = glyphPointSize(menuFontSize: fontSize)
        let slot = showsGlyph ? slotSize(pointSize: glyphSize) : .zero
        let gap = showsGlyph ? DesignTokens.Widget.largePercentGap : 0
        let width = (slot.width + gap + textSize.width).rounded(.up)
        guard width > 0, height > 0 else {
            return nil
        }
        let charge = charge(of: reading)
        let symbol = BatteryGlyph.symbolName(percent: charge.percent, isCharging: charge.isCharging)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { bounds in
            let textY = (bounds.height - textSize.height) / 2
            if showsGlyph {
                // The slot's middle sits on the middle of the number's capitals.
                let middle = textY - number.descender + number.capHeight / 2
                drawGlyph(
                    named: symbol,
                    pointSize: glyphSize,
                    in: NSRect(x: 0, y: middle - slot.height / 2, width: slot.width, height: slot.height)
                )
            }
            numberText.draw(at: NSPoint(x: slot.width + gap, y: textY))
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Measures and drawing

    nonisolated private static func numberFont(pointSize: CGFloat) -> NSFont {
        NSFont.monospacedDigitSystemFont(
            ofSize: pointSize + DesignTokens.Widget.largePercentGrowth,
            weight: .semibold
        )
    }

    nonisolated private static func glyphPointSize(menuFontSize: CGFloat) -> CGFloat {
        menuFontSize - DesignTokens.Widget.largePercentGlyphShrink
    }

    /// The charge and the charging state of a battery reading; none for any other reading.
    nonisolated private static func charge(of reading: WidgetReading) -> (percent: Int?, isCharging: Bool) {
        switch reading {
        case .battery(let percent, let state): (percent, state == .charging)
        case .power(let value): (value.percent, value.state == .charging)
        default: (nil, false)
        }
    }

    /// The widest width and the tallest height of the glyphs the widget can draw, rounded up.
    nonisolated private static func slotSize(pointSize: CGFloat) -> NSSize {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        var size = NSSize.zero
        for name in BatteryGlyph.symbolNames {
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            else {
                continue
            }
            size.width = max(size.width, symbol.size.width)
            size.height = max(size.height, symbol.size.height)
        }
        return NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    /// The glyph as a template image of the slot's size, centred in it.
    nonisolated private static func drawnSlot(symbol name: String, pointSize: CGFloat, size: NSSize) -> NSImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let image = NSImage(size: size, flipped: false) { bounds in
            drawGlyph(named: name, pointSize: pointSize, in: bounds)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws the glyph centred in the rectangle; a name the system does not know draws nothing.
    nonisolated private static func drawGlyph(named name: String, pointSize: CGFloat, in rect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else {
            return
        }
        let size = symbol.size
        symbol.draw(in: NSRect(
            x: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2,
            width: size.width,
            height: size.height
        ))
    }
}
