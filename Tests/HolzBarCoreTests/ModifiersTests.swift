import Foundation
import Testing
@testable import HolzBarCore

@Suite("Modifiers")
struct ModifiersTests {
    @Test("No modifier is always refused")
    func noModifierIsRefused() {
        let modifiers: Modifiers = []
        #expect(modifiers.rejection(refusesOptionOnly: true) == .missing)
        #expect(modifiers.rejection(refusesOptionOnly: false) == .missing)
    }

    @Test("Shift alone is always refused")
    func shiftAloneIsRefused() {
        let modifiers: Modifiers = [.shift]
        #expect(modifiers.rejection(refusesOptionOnly: true) == .shiftOnly)
        #expect(modifiers.rejection(refusesOptionOnly: false) == .shiftOnly)
    }

    @Test("Option alone is refused from macOS 15")
    func optionAloneIsRefusedFromMacOS15() {
        let optionOnly: [Modifiers] = [[.option], [.option, .shift]]
        for modifiers in optionOnly {
            #expect(modifiers.rejection(refusesOptionOnly: true) == .optionOnly)
            #expect(modifiers.rejection(refusesOptionOnly: false) == nil)
        }
    }

    @Test("Option with Command or Control is accepted")
    func optionWithCommandOrControlIsAccepted() {
        let combinations: [Modifiers] = [
            [.option, .command],
            [.option, .control],
            [.option, .shift, .command],
            [.control, .option, .shift],
        ]
        for modifiers in combinations {
            #expect(modifiers.rejection(refusesOptionOnly: true) == nil)
            #expect(modifiers.rejection(refusesOptionOnly: false) == nil)
        }
    }

    @Test("Command or Control combinations are accepted")
    func commandOrControlCombinationsAreAccepted() {
        let combinations: [Modifiers] = [
            [.command],
            [.control],
            [.command, .shift],
            [.control, .shift],
            [.control, .command],
        ]
        for modifiers in combinations {
            #expect(modifiers.rejection(refusesOptionOnly: true) == nil)
            #expect(modifiers.rejection(refusesOptionOnly: false) == nil)
        }
    }

    @Test("Raw values keep the stored hotkeys")
    func rawValuesKeepTheStoredHotkeys() throws {
        #expect(Modifiers.control.rawValue == 1)
        #expect(Modifiers.option.rawValue == 2)
        #expect(Modifiers.shift.rawValue == 4)
        #expect(Modifiers.command.rawValue == 8)

        let modifiers: Modifiers = [.option, .command]
        let data = try JSONEncoder().encode(modifiers)
        #expect(try JSONDecoder().decode(Modifiers.self, from: data) == modifiers)
    }

    @Test("Symbols follow the system order")
    func symbolsFollowTheSystemOrder() {
        let modifiers: Modifiers = [.command, .shift, .option, .control]
        #expect(modifiers.symbolicValue == "⌃⌥⇧⌘")
    }
}
