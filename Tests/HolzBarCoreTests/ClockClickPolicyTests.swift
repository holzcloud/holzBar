import Testing

@testable import HolzBarCore

@Suite("ClockClickPolicy")
struct ClockClickPolicyTests {
    @Test("With the setting on the clock's click is bridged")
    func clockOn() {
        #expect(ClockClickPolicy.bridges(item: "com.apple.menuextra.clock", clockOpensNotificationCenter: true))
    }

    @Test("With the setting off the clock's click passes through unchanged")
    func clockOff() {
        #expect(!ClockClickPolicy.bridges(item: "com.apple.menuextra.clock", clockOpensNotificationCenter: false))
    }

    @Test("The other system items and the overflow button are bridged whatever the setting says")
    func others() {
        for setting in [true, false] {
            #expect(ClockClickPolicy.bridges(item: "com.apple.menuextra.battery", clockOpensNotificationCenter: setting))
            #expect(ClockClickPolicy.bridges(item: "com.apple.menuextra.wifi", clockOpensNotificationCenter: setting))
            #expect(ClockClickPolicy.bridges(item: nil, clockOpensNotificationCenter: setting))
        }
    }

    @Test("Only the clock's identifier is the clock")
    func isClock() {
        #expect(ClockClickPolicy.isClock("com.apple.menuextra.clock"))
        #expect(!ClockClickPolicy.isClock("com.apple.menuextra.clock2"))
        #expect(!ClockClickPolicy.isClock(nil))
    }
}
