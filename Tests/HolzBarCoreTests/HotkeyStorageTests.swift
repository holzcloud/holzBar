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
}
