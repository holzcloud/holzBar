//
//  DeviceBatteryWidget.swift
//  holzBar
//

import AppKit

/// What only the Lowest Device Battery widget draws and says (D-26).
///
/// The menu bar shows the kind of the accessory that has the lowest level as a symbol before the
/// percent, in a slot as wide as the widest symbol of the set, so a different device never moves
/// the item or its text. The device's name is personal data: it appears only in the tooltip and in
/// the value VoiceOver reads, never in the menu bar's text or in a picture of the widget.
enum DeviceBatteryWidget {
    /// Whether the widget is the Lowest Device Battery text widget.
    static func isWidget(_ definition: WidgetDefinition) -> Bool {
        definition.kind == .text && definition.source == .deviceBattery
    }

    /// The symbol as a template image centred in a slot as wide as the widest symbol of
    /// ``ConnectedDeviceList/widgetSymbols``; `nil` when the system has no symbol of that name.
    static func slotImage(symbol: String, font: NSFont) -> NSImage? {
        guard NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
            return nil
        }
        let pointSize = font.pointSize
        let size = slotSize(pointSize: pointSize)
        return drawnSlot(symbol: symbol, pointSize: pointSize, width: size.width, height: size.height)
    }

    /// The width of the symbol slot: the widest symbol of the set, rounded up.
    static func slotWidth(font: NSFont) -> CGFloat {
        slotSize(pointSize: font.pointSize).width
    }

    /// The tooltip: the device's name, verbatim and nothing else; with no level, or while Read
    /// battery levels is off, the line that says why.
    static func tooltip(for reading: WidgetReading, readsBattery: Bool) -> String {
        if readsBattery, case .device(let device) = reading {
            return device.name
        }
        return missingLevelText(readsBattery: readsBattery)
    }

    /// What VoiceOver says instead of the "<name>, 82 percent" of ``WidgetSpeech`` when there is
    /// no level to say; `nil` when the widget has one, so ``WidgetSpeech`` speaks it.
    static func spokenValue(for reading: WidgetReading, readsBattery: Bool) -> String? {
        if readsBattery, case .device = reading {
            return nil
        }
        return missingLevelText(readsBattery: readsBattery)
    }

    private static func missingLevelText(readsBattery: Bool) -> String {
        readsBattery
            ? String(localized: "No device reports a battery level")
            : String(localized: "Read battery levels is off in Accessory alerts")
    }

    /// The widest width and the tallest height of the symbols the widget can show.
    private static func slotSize(pointSize: CGFloat) -> NSSize {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        var size = NSSize.zero
        for name in ConnectedDeviceList.widgetSymbols {
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

    /// Draws the symbol centred. It takes plain values only: the image's drawing block runs
    /// whenever and wherever the image is drawn, so it holds nothing of the main actor.
    nonisolated private static func drawnSlot(
        symbol name: String,
        pointSize: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> NSImage? {
        guard width > 0, height > 0 else {
            return nil
        }
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { bounds in
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            else {
                return true
            }
            let size = symbol.size
            symbol.draw(in: NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }
}
