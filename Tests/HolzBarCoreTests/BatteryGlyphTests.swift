import Testing
@testable import HolzBarCore

@Suite("BatteryGlyph")
struct BatteryGlyphTests {
    @Test("The glyph is the battery symbol nearest the charge")
    func nearestStep() {
        #expect(BatteryGlyph.symbolName(percent: 0, isCharging: false) == "battery.0percent")
        #expect(BatteryGlyph.symbolName(percent: 12, isCharging: false) == "battery.0percent")
        #expect(BatteryGlyph.symbolName(percent: 13, isCharging: false) == "battery.25percent")
        #expect(BatteryGlyph.symbolName(percent: 37, isCharging: false) == "battery.25percent")
        #expect(BatteryGlyph.symbolName(percent: 62, isCharging: false) == "battery.50percent")
        #expect(BatteryGlyph.symbolName(percent: 63, isCharging: false) == "battery.75percent")
        #expect(BatteryGlyph.symbolName(percent: 88, isCharging: false) == "battery.100percent")
        #expect(BatteryGlyph.symbolName(percent: 100, isCharging: false) == "battery.100percent")
    }

    @Test("A missing or out-of-range reading is clamped, and a charging battery shows the bolt")
    func edgesAndCharging() {
        #expect(BatteryGlyph.symbolName(percent: nil, isCharging: false) == "battery.0percent")
        #expect(BatteryGlyph.symbolName(percent: -20, isCharging: false) == "battery.0percent")
        #expect(BatteryGlyph.symbolName(percent: 140, isCharging: false) == "battery.100percent")
        for percent in [nil, 0, 40, 100] as [Int?] {
            #expect(BatteryGlyph.symbolName(percent: percent, isCharging: true) == "battery.100percent.bolt")
        }
    }

    @Test("The state symbol is a bolt while charging, a plug on the adapter and none on battery")
    func stateSymbol() {
        #expect(BatteryGlyph.stateSymbolName(for: .charging) == "bolt.fill")
        #expect(BatteryGlyph.stateSymbolName(for: .charged) == "powerplug.fill")
        #expect(BatteryGlyph.stateSymbolName(for: .onAdapter) == "powerplug.fill")
        #expect(BatteryGlyph.stateSymbolName(for: .onBattery) == nil)
        #expect(BatteryGlyph.stateSymbolName(for: nil) == nil)
    }

    @Test("Every glyph the widget can draw is listed, so its slot fits the widest")
    func symbolNames() {
        #expect(
            BatteryGlyph.symbolNames == [
                "battery.0percent", "battery.25percent", "battery.50percent", "battery.75percent",
                "battery.100percent", "battery.100percent.bolt",
            ]
        )
        for percent in 0...100 {
            #expect(BatteryGlyph.symbolNames.contains(BatteryGlyph.symbolName(percent: percent, isCharging: false)))
        }
    }
}
