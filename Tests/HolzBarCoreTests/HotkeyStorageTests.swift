import Foundation
import Testing
@testable import HolzBarCore

@Suite("Hotkeys")
struct HotkeyStorageTests {
    @Test("The hotkey signature never changes")
    func signatureNeverChanges() {
        #expect(HotkeyStorage.signature == 1231250720)
    }

    @Test("Stored hotkey actions never change")
    func storedActionsNeverChange() {
        #expect(HotkeyAction.allCases.map(\.rawValue) == [
            "ToggleHiddenSection",
            "ToggleAlwaysHiddenSection",
            "ShowHiddenSectionTemporarily",
            "SearchMenuBarItems",
            "EnableIceBar",
            "ToggleApplicationMenus",
            "ToggleAutoRehide",
            "ToggleZenMode",
            "ShowItemHints",
        ])
    }

    @Test("A stored key combination is two numbers")
    func keyCombinationIsTwoNumbers() throws {
        let data = HotkeyStorage.encode(key: 49, modifiers: 10)
        #expect(String(decoding: data, as: UTF8.self) == "[49,10]")
        let decoded = try #require(HotkeyStorage.decode(data))
        #expect(decoded.key == 49)
        #expect(decoded.modifiers == 10)
    }

    @Test("A damaged stored hotkey is ignored")
    func damagedHotkeyIgnored() {
        #expect(HotkeyStorage.decode(Data("[49]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("[1,2,3]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("not json".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data()) == nil)
    }

    @Test("A key code outside 0 to 127 is ignored")
    func keyCodeOutOfRangeIgnored() {
        #expect(HotkeyStorage.decode(Data("[128,8]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("[-1,8]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("[99999,8]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("[0,8]".utf8))?.key == 0)
        #expect(HotkeyStorage.decode(Data("[127,8]".utf8))?.key == 127)
    }

    @Test("Unknown modifier bits are ignored")
    func unknownModifierBitsIgnored() {
        #expect(HotkeyStorage.decode(Data("[49,256]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("[49,16]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("[49,-1]".utf8)) == nil)
        #expect(HotkeyStorage.decode(Data("[49,15]".utf8))?.modifiers == 15)
        #expect(HotkeyStorage.decode(Data("[49,0]".utf8))?.modifiers == 0)
    }

    @Test("An action is stored by its raw value")
    func actionStoredByRawValue() throws {
        let data = try JSONEncoder().encode(HotkeyAction.enableShelf)
        #expect(String(decoding: data, as: UTF8.self) == "\"EnableIceBar\"")
        #expect(try JSONDecoder().decode(HotkeyAction.self, from: data) == .enableShelf)
    }

    @Test("A stored hotkey without a modifier is not loaded")
    func storedHotkeyWithoutModifierIsRefused() {
        // Space (49), Return (36) or a letter alone would be taken from every app.
        #expect(HotkeyStorage.loadRejection(modifiers: 0, refusesOptionOnly: true) == .missing)
        #expect(HotkeyStorage.loadRejection(modifiers: 0, refusesOptionOnly: false) == .missing)
        #expect(HotkeyStorage.loadRejection(modifiers: Modifiers.shift.rawValue, refusesOptionOnly: false) == .shiftOnly)
    }

    @Test("Option-only hotkeys are loaded only where the system registers them")
    func optionOnlyHotkeys() {
        let option = Modifiers.option.rawValue
        let optionShift = Modifiers([.option, .shift]).rawValue
        #expect(HotkeyStorage.loadRejection(modifiers: option, refusesOptionOnly: true) == .optionOnly)
        #expect(HotkeyStorage.loadRejection(modifiers: optionShift, refusesOptionOnly: true) == .optionOnly)
        #expect(HotkeyStorage.loadRejection(modifiers: option, refusesOptionOnly: false) == nil)
    }

    @Test("A stored hotkey with a real modifier is loaded")
    func storedHotkeyWithModifierIsLoaded() {
        for modifiers: Modifiers in [.command, .control, [.command, .shift], [.control, .option], [.option, .command]] {
            #expect(HotkeyStorage.loadRejection(modifiers: modifiers.rawValue, refusesOptionOnly: true) == nil)
        }
    }

    @Test("A stored hotkey whose combination an earlier one uses is not loaded")
    func duplicateCombinationsLoseToTheFirst() {
        let command = Modifiers.command.rawValue
        let control = Modifiers.control.rawValue
        let duplicates = HotkeyStorage.duplicateStorageKeys(inLoadOrder: [
            ("SearchMenuBarItems", 40, command),
            ("ToggleZenMode", 40, control),
            ("ApplyProfile:Work", 40, command),
            ("OpenItem:com.example.Clock", 40, command),
            ("ApplyProfile:Home", 41, command),
        ])
        #expect(duplicates == ["ApplyProfile:Work", "OpenItem:com.example.Clock"])
    }

    @Test("Stored hotkeys with different combinations are all loaded")
    func distinctCombinationsAllLoad() {
        let command = Modifiers.command.rawValue
        #expect(HotkeyStorage.duplicateStorageKeys(inLoadOrder: []).isEmpty)
        #expect(HotkeyStorage.duplicateStorageKeys(inLoadOrder: [
            ("ToggleHiddenSection", 1, command),
            ("ToggleAlwaysHiddenSection", 2, command),
            ("ApplyProfile:Work", 1, Modifiers([.command, .shift]).rawValue),
        ]).isEmpty)
    }
}
