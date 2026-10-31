import Foundation
import Testing
@testable import HolzBarCore

@Suite("AccessoryRefreshPolicy")
struct AccessoryRefreshPolicyTests {
    private let read = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The coarse refresh is five minutes")
    func interval() {
        #expect(AccessoryRefreshPolicy.interval == 300)
    }

    @Test("With a battery-reporting accessory the next refresh is the last read plus the interval")
    func nextWithAnAccessory() {
        #expect(AccessoryRefreshPolicy.next(hasBatteryAccessory: true, lastRead: read) == read.addingTimeInterval(300))
    }

    @Test("Without one there is no next refresh")
    func nextWithoutAnAccessory() {
        #expect(AccessoryRefreshPolicy.next(hasBatteryAccessory: false, lastRead: read) == nil)
    }
}
