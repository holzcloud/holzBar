import Foundation
import Testing
@testable import HolzBarCore

@Suite("ConnectedDeviceList")
struct ConnectedDeviceListTests {
    private func device(
        _ name: String,
        address: String = "aa-bb-cc-dd-ee-01",
        major: Int = 4,
        minor: Int = 6
    ) throws -> AccessoryDevice {
        try #require(AccessoryDevice(address: address, name: name, majorClass: major, minorClass: minor))
    }

    private func battery(
        _ name: String,
        _ percent: Int,
        id: String? = nil,
        category: String? = nil
    ) -> AccessoryBattery {
        AccessoryBattery(id: id ?? "id-" + name + "-\(percent)", name: name, percent: percent, lowWarnLevel: nil, category: category)
    }

    @Test("Nothing connected and nothing paired gives no row and no lowest battery")
    func empty() {
        #expect(ConnectedDeviceList.rows(connected: [], disconnected: [], batteries: []).isEmpty)
        #expect(ConnectedDeviceList.lowest([]) == nil)
    }

    @Test("A battery with no Bluetooth device is one connected row with the symbol of its category")
    func batteryOnly() {
        let rows = ConnectedDeviceList.rows(
            connected: [],
            disconnected: [],
            batteries: [battery("Magic Keyboard", 64, category: "Keyboard")]
        )
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Magic Keyboard")
        #expect(rows.first?.percent == 64)
        #expect(rows.first?.isConnected == true)
        #expect(rows.first?.symbol == "keyboard")
        #expect(rows.first?.parts == [])
    }

    @Test("A device with several battery parts is one row at its lowest part, parts ascending")
    func severalParts() throws {
        let rows = ConnectedDeviceList.rows(
            connected: [try device("AirPods Pro")],
            disconnected: [],
            batteries: [battery("AirPods Pro", 80), battery("AirPods Pro", 72), battery("AirPods Pro", 100)]
        )
        #expect(rows.count == 1)
        #expect(rows.first?.percent == 72)
        #expect(rows.first?.parts == [72, 80, 100])
        #expect(rows.first?.symbol == "airpodspro")
        #expect(rows.first?.isConnected == true)
    }

    @Test("Names that differ in case, diacritics or surrounding space are one key")
    func keys() {
        #expect(ConnectedDeviceList.key(for: "airpods pro") == ConnectedDeviceList.key(for: "AirPods Pro"))
        #expect(ConnectedDeviceList.key(for: "Café") == ConnectedDeviceList.key(for: "Cafe"))
        #expect(ConnectedDeviceList.key(for: " Magic Mouse ") == ConnectedDeviceList.key(for: "Magic Mouse"))
        #expect(ConnectedDeviceList.key(for: "Magic Mouse") != ConnectedDeviceList.key(for: "Magic Keyboard"))
    }

    @Test("Names in different forms merge into one row that shows the first device's name")
    func mergedNames() throws {
        let rows = ConnectedDeviceList.rows(
            connected: [try device("Ana's AirPods", address: "aa-bb-cc-dd-ee-01"), try device("ana's airpods", address: "aa-bb-cc-dd-ee-02")],
            disconnected: [],
            batteries: [battery(" Ana's AirPods ", 40, id: "a"), battery("Ana's AirPods", 55, id: "b")]
        )
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Ana's AirPods")
        #expect(rows.first?.percent == 40)
        #expect(rows.first?.parts == [40, 55])
    }

    @Test("A connected device without a battery is one row without a level")
    func connectedWithoutBattery() throws {
        let rows = ConnectedDeviceList.rows(connected: [try device("Sony WH-1000XM5")], disconnected: [], batteries: [])
        #expect(rows.count == 1)
        #expect(rows.first?.isConnected == true)
        #expect(rows.first?.percent == nil)
        #expect(rows.first?.symbol == "headphones")
    }

    @Test("A paired device that is not connected is a grey row without a level, even beside other batteries")
    func disconnectedDevice() throws {
        let rows = ConnectedDeviceList.rows(
            connected: [],
            disconnected: [try device("Sony WH-1000XM5")],
            batteries: [battery("Magic Mouse", 90, category: "Mouse")]
        )
        #expect(rows.count == 2)
        #expect(rows.first?.name == "Magic Mouse")
        #expect(rows.first?.isConnected == true)
        #expect(rows.last?.name == "Sony WH-1000XM5")
        #expect(rows.last?.isConnected == false)
        #expect(rows.last?.percent == nil)
        #expect(rows.last?.parts == [])
    }

    @Test("A name that is paired and has a battery counts as connected, and never shows twice")
    func batteryOnlyExistsWhileConnected() throws {
        let rows = ConnectedDeviceList.rows(
            connected: [],
            disconnected: [try device("Magic Keyboard", major: 5, minor: 0x10)],
            batteries: [battery("Magic Keyboard", 64, category: "Keyboard")]
        )
        #expect(rows.count == 1)
        #expect(rows.first?.isConnected == true)
        #expect(rows.first?.percent == 64)
    }

    @Test("A USB and a Bluetooth keyboard with the same name merge at the lower level")
    func sameNameMerges() {
        let rows = ConnectedDeviceList.rows(
            connected: [],
            disconnected: [],
            batteries: [
                battery("Magic Keyboard", 80, id: "usb", category: "Keyboard"),
                battery("Magic Keyboard", 64, id: "bt", category: "Keyboard"),
            ]
        )
        #expect(rows.count == 1)
        #expect(rows.first?.percent == 64)
    }

    @Test("Connected rows come first by name, grey rows follow by name")
    func order() throws {
        let rows = ConnectedDeviceList.rows(
            connected: [try device("Speaker 10", address: "aa-bb-cc-dd-ee-01"), try device("Speaker 2", address: "aa-bb-cc-dd-ee-02")],
            disconnected: [try device("Alpha", address: "aa-bb-cc-dd-ee-03"), try device("Zulu", address: "aa-bb-cc-dd-ee-04")],
            batteries: [battery("Magic Mouse", 90, category: "Mouse")]
        )
        #expect(rows.map(\.name) == ["Magic Mouse", "Speaker 2", "Speaker 10", "Alpha", "Zulu"])
        #expect(rows.map(\.isConnected) == [true, true, true, false, false])
    }

    @Test("At most 20 rows, and a grey row is cut before a connected one")
    func cap() throws {
        let connected = try (0..<25).map { index in
            try device("Device \(String(format: "%02d", index))", address: String(format: "aa-bb-cc-dd-ee-%02x", index))
        }
        let grey = try (0..<5).map { index in
            try device("Grey \(index)", address: String(format: "bb-bb-cc-dd-ee-%02x", index))
        }
        let rows = ConnectedDeviceList.rows(connected: connected, disconnected: grey, batteries: [])
        #expect(rows.count == ConnectedDeviceList.maximumRows)
        #expect(rows.allSatisfy { $0.isConnected })
    }

    @Test("The symbol of a battery follows its name, then its category")
    func batterySymbols() {
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "AirPods Pro", category: nil) == "airpodspro")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "AirPods", category: nil) == "airpods")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "Thing", category: "Keyboard") == "keyboard")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "Thing", category: "Mouse") == "computermouse")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "Thing", category: "Trackpad") == "computermouse")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "Thing", category: "Headset") == "headphones")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "Thing", category: "Headphones") == "headphones")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "Thing", category: "Gamepad") == "battery.25percent")
        #expect(ConnectedDeviceList.symbol(forBatteryNamed: "Thing", category: nil) == "battery.25percent")
    }

    @Test("The lowest battery is the smallest level; a tie goes to the first name, then the id")
    func lowest() {
        let list = [battery("Zed", 40, id: "z"), battery("Alpha", 20, id: "a2"), battery("Alpha", 20, id: "a1", category: "Keyboard"), battery("Mid", 90, id: "m")]
        let lowest = ConnectedDeviceList.lowest(list)
        #expect(lowest?.percent == 20)
        #expect(lowest?.name == "Alpha")
        #expect(lowest?.symbol == "keyboard")
    }

    @Test("The widget offers the symbols the rule can give")
    func widgetSymbols() {
        for symbol in [
            "airpods", "airpodspro", "headphones", "speaker.wave.2", "keyboard", "computermouse",
            "battery.25percent", "dot.radiowaves.left.and.right",
        ] {
            #expect(ConnectedDeviceList.widgetSymbols.contains(symbol))
        }
        #expect(ConnectedDeviceList.unknownSymbol == "dot.radiowaves.left.and.right")
    }
}
