import Testing
@testable import HolzBarMacOS27Core

@Suite("SystemItems27")
struct SystemItems27Tests {
    @Test("Every drawn system item is allowed")
    func drawnItemsAreAllowed() {
        for number in SystemItems27.drawn {
            #expect(SystemItems27.allowed.contains(number))
        }
    }

    @Test("The allowlist is the measured range, 0 through 127")
    func allowedIsTheMeasuredRange() {
        #expect(SystemItems27.highestMeasured == 127)
        #expect(SystemItems27.allowed.lowerBound == 0)
        #expect(SystemItems27.allowed.upperBound == SystemItems27.highestMeasured)
        #expect(SystemItems27.allowed.count == 128)
    }

    @Test("Nothing beyond the measurement is allowed")
    func nothingBeyondTheMeasurementIsAllowed() {
        #expect(!SystemItems27.allowed.contains(SystemItems27.highestMeasured + 1))
        #expect(!SystemItems27.allowed.contains(-1))
    }
}
