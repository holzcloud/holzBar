import Testing
@testable import HolzBarCore

@Suite("ItemIconChoice")
struct ItemIconChoiceTests {
    @Test("A chosen image wins")
    func chosenImageWins() {
        let file = ItemIconChoice.Stored.file("A1.png")
        #expect(ItemIconChoice.source(stored: file, hasCustomImage: true, hasCapture: true, hasAppIcon: true) == .custom)
        // A missing file falls back to the next choice.
        #expect(ItemIconChoice.source(stored: file, hasCustomImage: false, hasCapture: true, hasAppIcon: true) == .captured)
        #expect(ItemIconChoice.source(stored: nil, hasCustomImage: false, hasCapture: true, hasAppIcon: true) == .captured)
        #expect(ItemIconChoice.source(stored: nil, hasCustomImage: false, hasCapture: false, hasAppIcon: true) == .appIcon)
        #expect(ItemIconChoice.source(stored: nil, hasCustomImage: false, hasCapture: false, hasAppIcon: false) == .name)
    }

    @Test("Use App Icon wins over a capture")
    func useAppIconWinsOverCapture() {
        #expect(ItemIconChoice.source(stored: .appIcon, hasCustomImage: false, hasCapture: true, hasAppIcon: true) == .appIcon)
        #expect(ItemIconChoice.source(stored: .appIcon, hasCustomImage: false, hasCapture: true, hasAppIcon: false) == .captured)
    }

    @Test("Stored choices parse")
    func storedChoicesParse() {
        #expect(ItemIconChoice.parse("app") == .appIcon)
        #expect(ItemIconChoice.parse(nil) == nil)
        let name = "6F1C2B4A-0D3E-4F5A-9B8C-7D6E5F4A3B2C.png"
        #expect(ItemIconChoice.parse("file:" + name) == .file(name))
        for stored in [ItemIconChoice.Stored.appIcon, .file(name)] {
            #expect(ItemIconChoice.parse(ItemIconChoice.storedValue(stored)) == stored)
        }
        #expect(ItemIconChoice.parse("file:../Preferences/x.png") == nil)
        #expect(ItemIconChoice.parse("file:a/b.png") == nil)
        #expect(ItemIconChoice.parse("file:..png") == nil)
        #expect(ItemIconChoice.parse("file:icon.jpg") == nil)
        #expect(ItemIconChoice.parse("file:.png") == nil)
        #expect(ItemIconChoice.parse("icon.png") == nil)
        #expect(ItemIconChoice.parse("App") == nil)
    }

    @Test("Hex colours round-trip")
    func hexColoursRoundTrip() throws {
        let components = try #require(HexColor.components("#FF8000"))
        #expect(components.red == 1)
        #expect(components.blue == 0)
        #expect(HexColor.string(red: components.red, green: components.green, blue: components.blue) == "#FF8000")
        #expect(HexColor.components("#FF80") == nil)
        #expect(HexColor.components("#GG0000") == nil)
        #expect(HexColor.string(red: 2, green: -1, blue: 0.5) == "#FF0080")
    }
}
