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

    @Test("The four hideable items are the four drawn numbers")
    func hideableItemsAreTheDrawnNumbers() {
        #expect(Set(SystemItem27.allCases.map(\.number)) == SystemItems27.drawn)
        #expect(SystemItem27.battery.number == 0)
        #expect(SystemItem27.clock.number == 2)
        #expect(SystemItem27.wifi.number == 6)
        #expect(SystemItem27.controlCentre.number == 8)
    }

    @Test("The stored names never change")
    func storedNames() {
        #expect(SystemItem27.allCases.map(\.rawValue) == ["battery", "clock", "wifi", "controlCentre"])
    }

    @Test("A hidden item's key has a colon, which no bundle identifier can have")
    func concealedKeys() {
        #expect(SystemItems27.concealedKey(for: .clock) == "system-item:2")
        #expect(SystemItems27.concealedKey(for: .controlCentre) == "system-item:8")
        for item in SystemItem27.allCases {
            #expect(SystemItems27.concealedKey(for: item).contains(":"))
        }
    }

    @Test("With nothing concealed every number is allowed, in ascending order")
    func allowedNumbersWithNothingConcealed() {
        #expect(SystemItems27.allowedNumbers(concealing: []) == Array(0...127))
    }

    @Test("A concealed item leaves its number out of the allowed ones")
    func allowedNumbersWithOneConcealed() {
        let numbers = SystemItems27.allowedNumbers(concealing: ["system-item:2"])
        #expect(numbers.count == 127)
        #expect(!numbers.contains(2))
        #expect(numbers.contains(0))
        #expect(numbers == numbers.sorted())
    }

    @Test("Two concealed items leave two numbers out")
    func allowedNumbersWithTwoConcealed() {
        let numbers = SystemItems27.allowedNumbers(concealing: ["system-item:2", "system-item:8"])
        #expect(numbers.count == 126)
        #expect(!numbers.contains(2))
        #expect(!numbers.contains(8))
    }

    @Test("Only the four measured numbers can be hidden")
    func unknownKeysHideNothing() {
        let everything = Array(0...127)
        for key in ["system-item:1", "system-item:99", "system-item:x", "system-item:", "system-item:-2", "com.example.app", ""] {
            #expect(SystemItems27.allowedNumbers(concealing: [key]) == everything, "\(key)")
        }
    }

    @Test("Stored names are validated: unknown and wrongly cased names are ignored, duplicates collapse")
    func hiddenFromStored() {
        #expect(SystemItems27.hidden(fromStored: ["clock", "bogus", "clock", "Clock"]) == [.clock])
        #expect(SystemItems27.hidden(fromStored: []).isEmpty)
    }

    @Test("Names are stored ordered by number")
    func storedNamesAreOrdered() {
        #expect(SystemItems27.storedNames(of: [.wifi, .clock]) == ["clock", "wifi"])
        #expect(SystemItems27.storedNames(of: []).isEmpty)
    }

    @Test("Nothing is hidden while the module is off")
    func moduleOff() {
        #expect(SystemItems27.concealed(stored: [.clock], moduleIsOn: false, shelfIsOn: false).isEmpty)
    }

    @Test("Nothing is hidden while the Shelf is on")
    func shelfOn() {
        #expect(SystemItems27.concealed(stored: [.clock], moduleIsOn: true, shelfIsOn: true).isEmpty)
        #expect(SystemItems27.concealed(stored: [.clock], moduleIsOn: false, shelfIsOn: true).isEmpty)
    }

    @Test("The stored items are hidden with the module on and the Shelf off")
    func moduleOnShelfOff() {
        #expect(SystemItems27.concealed(stored: [.clock, .wifi], moduleIsOn: true, shelfIsOn: false) == [.clock, .wifi])
    }

    @Test("The layout entries put each hidden item in the hidden section")
    func layoutEntries() {
        #expect(SystemItems27.layoutEntries(for: [.clock]) == ["system-item:2": .hidden])
        #expect(SystemItems27.layoutEntries(for: []).isEmpty)
    }
}
