import Foundation
import Testing
@testable import HolzBarCore

@Suite("AccessoryAlertOptions")
struct AccessoryAlertOptionsTests {
    private let device = AccessoryDevice(
        address: "aa-bb-cc-dd-ee-ff", name: "Headphones", majorClass: 4, minorClass: 6
    )

    @Test("Connect alerts are on and disconnect alerts are off by default")
    func defaults() {
        #expect(AccessoryAlertOptions.default.connect)
        #expect(!AccessoryAlertOptions.default.disconnect)
    }

    @Test("An event is allowed only when the switch of its kind is on")
    func allows() throws {
        let device = try #require(device)
        let connected = AccessoryEvent.connected(device)
        let disconnected = AccessoryEvent.disconnected(device)
        let standard = AccessoryAlertOptions.default
        #expect(standard.allows(connected))
        #expect(!standard.allows(disconnected))
        let both = AccessoryAlertOptions(connect: true, disconnect: true)
        #expect(both.allows(connected))
        #expect(both.allows(disconnected))
        let none = AccessoryAlertOptions(connect: false, disconnect: false)
        #expect(!none.allows(connected))
        #expect(!none.allows(disconnected))
        let onlyDisconnect = AccessoryAlertOptions(connect: false, disconnect: true)
        #expect(!onlyDisconnect.allows(connected))
        #expect(onlyDisconnect.allows(disconnected))
    }

    @Test("Low-battery alerts are on at 20 percent by default")
    func lowBatteryDefaults() {
        #expect(AccessoryAlertOptions.default.lowBattery)
        #expect(AccessoryAlertOptions.default.lowBatteryLevel == 20)
        #expect(AccessoryAlertOptions(connect: true, disconnect: false).lowBatteryLevel == 20)
        #expect(AccessoryAlertOptions.lowBatteryLevelRange == 10...30)
    }

    @Test("The level is kept in 10 to 30, rounded, and 20 when it is not a number")
    func clampedLevel() {
        #expect(AccessoryAlertOptions.clampedLevel(20) == 20)
        #expect(AccessoryAlertOptions.clampedLevel(10) == 10)
        #expect(AccessoryAlertOptions.clampedLevel(30) == 30)
        #expect(AccessoryAlertOptions.clampedLevel(5) == 10)
        #expect(AccessoryAlertOptions.clampedLevel(-40) == 10)
        #expect(AccessoryAlertOptions.clampedLevel(99) == 30)
        #expect(AccessoryAlertOptions.clampedLevel(14.6) == 15)
        #expect(AccessoryAlertOptions.clampedLevel(14.4) == 14)
        #expect(AccessoryAlertOptions.clampedLevel(.nan) == 20)
        #expect(AccessoryAlertOptions.clampedLevel(.infinity) == 20)
        #expect(AccessoryAlertOptions.clampedLevel(-.infinity) == 20)
    }

    @Test("Low-battery alerts follow their switch")
    func allowsLowBattery() {
        #expect(AccessoryAlertOptions.default.allowsLowBattery)
        var options = AccessoryAlertOptions.default
        options.lowBattery = false
        #expect(!options.allowsLowBattery)
    }
}
