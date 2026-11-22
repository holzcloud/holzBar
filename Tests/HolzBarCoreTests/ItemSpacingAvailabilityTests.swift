import Testing
@testable import HolzBarCore

@Suite("Item spacing availability")
struct ItemSpacingAvailabilityTests {
    @Test("Item spacing is available on macOS 14 to 26")
    func beforeMacOS27() {
        #expect(ItemSpacingAvailability.isAvailable(macOSMajor: 14))
        #expect(ItemSpacingAvailability.isAvailable(macOSMajor: 26))
    }

    @Test("On macOS 27 and later it follows what probe P7 showed")
    func fromMacOS27() {
        #expect(ItemSpacingAvailability.isAvailable(macOSMajor: 27) == ItemSpacingAvailability.worksOnMacOS27)
        #expect(ItemSpacingAvailability.isAvailable(macOSMajor: 28) == ItemSpacingAvailability.worksOnMacOS27)
    }

    @Test("It is off on macOS 27 until probe P7 shows macOS 27 honours the spacing keys")
    func offUntilProbe() {
        #expect(!ItemSpacingAvailability.worksOnMacOS27)
    }
}
