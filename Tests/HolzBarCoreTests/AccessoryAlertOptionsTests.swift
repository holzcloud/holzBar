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
}
