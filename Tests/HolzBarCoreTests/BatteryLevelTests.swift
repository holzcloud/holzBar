import Testing
@testable import HolzBarCore

@Suite("BatteryLevel")
struct BatteryLevelTests {
    @Test("The battery level is a whole percentage")
    func batteryLevelIsAWholePercentage() {
        #expect(BatteryLevel.percent(current: 37, maximum: 50) == 74)
        #expect(BatteryLevel.percent(current: 1, maximum: 3) == 33)
    }

    @Test("A battery without a maximum has no level")
    func batteryWithoutAMaximumHasNoLevel() {
        #expect(BatteryLevel.percent(current: 10, maximum: 0) == nil)
    }
}
