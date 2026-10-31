import Foundation
import Testing
@testable import HolzBarCore

@Suite("AccessoryDevice")
struct AccessoryDeviceTests {
    @Test("The class of device gives headphones, speakers, keyboards, pointers or other")
    func kindFromClass() {
        for minor in [6, 1, 2] {
            #expect(AccessoryKind(majorClass: 4, minorClass: minor) == .headphones)
        }
        for minor in [5, 8] {
            #expect(AccessoryKind(majorClass: 4, minorClass: minor) == .speaker)
        }
        for minor in [0x10, 0x30] {
            #expect(AccessoryKind(majorClass: 5, minorClass: minor) == .keyboard)
        }
        #expect(AccessoryKind(majorClass: 5, minorClass: 0x20) == .pointer)
    }

    @Test("Anything else, and odd values, are other")
    func kindOther() {
        #expect(AccessoryKind(majorClass: 5, minorClass: 0) == .other)
        #expect(AccessoryKind(majorClass: 1, minorClass: 6) == .other)
        #expect(AccessoryKind(majorClass: 0, minorClass: 0) == .other)
        #expect(AccessoryKind(majorClass: 4, minorClass: 3) == .other)
        #expect(AccessoryKind(majorClass: -1, minorClass: 6) == .other)
        #expect(AccessoryKind(majorClass: 4, minorClass: -6) == .other)
        #expect(AccessoryKind(majorClass: 256, minorClass: 6) == .other)
        #expect(AccessoryKind(majorClass: 4, minorClass: 1_000) == .other)
    }

    @Test("Every kind has a symbol, and an AirPods name wins over the kind")
    func symbols() throws {
        func symbol(_ name: String, _ major: Int, _ minor: Int) throws -> String {
            try #require(AccessoryDevice(address: "aa-bb-cc-dd-ee-ff", name: name, majorClass: major, minorClass: minor)).symbolName
        }
        #expect(try symbol("Headset", 4, 6) == "headphones")
        #expect(try symbol("Speaker", 4, 5) == "speaker.wave.2")
        #expect(try symbol("Keys", 5, 0x10) == "keyboard")
        #expect(try symbol("Mouse", 5, 0x20) == "computermouse")
        #expect(try symbol("Thing", 0, 0) == "dot.radiowaves.left.and.right")
        #expect(try symbol("Ana's AirPods Pro", 4, 6) == "airpodspro")
        #expect(try symbol("ANA'S AIRPODS PRO", 0, 0) == "airpodspro")
        #expect(try symbol("AirPods", 4, 6) == "airpods")
        #expect(try symbol("Ana's airpods", 5, 0x10) == "airpods")
    }

    @Test("An address in either form gives the hyphenated lowercase id, and a bad one gives nothing")
    func addressForm() throws {
        let colon = try #require(AccessoryDevice(address: "AA:BB:CC:DD:EE:FF", name: "A", majorClass: 4, minorClass: 6))
        let hyphen = try #require(AccessoryDevice(address: "aa-bb-cc-dd-ee-ff", name: "A", majorClass: 4, minorClass: 6))
        #expect(colon.id == "aa-bb-cc-dd-ee-ff")
        #expect(hyphen.id == "aa-bb-cc-dd-ee-ff")
        #expect(AccessoryDevice(address: "zz-bb-cc-dd-ee-ff", name: "A", majorClass: 4, minorClass: 6) == nil)
        #expect(AccessoryDevice(address: "aa-bb-cc", name: "A", majorClass: 4, minorClass: 6) == nil)
        #expect(AccessoryDevice(address: "aa-bb-cc-dd-ee-ff-00", name: "A", majorClass: 4, minorClass: 6) == nil)
        #expect(AccessoryDevice(address: "", name: "A", majorClass: 4, minorClass: 6) == nil)
        #expect(AccessoryDevice.normalizedAddress("Aa:bB:cC:Dd:eE:fF") == "aa-bb-cc-dd-ee-ff")
        #expect(AccessoryDevice.normalizedAddress("aa:bb-cc:dd:ee:ff") == nil)
    }

    @Test("A name is trimmed, cut to 80 bytes without splitting a character, and falls back to the address")
    func nameForm() throws {
        let trimmed = try #require(AccessoryDevice(address: "aa-bb-cc-dd-ee-ff", name: "  Ana's Mouse \n", majorClass: 5, minorClass: 0x20))
        #expect(trimmed.name == "Ana's Mouse")
        let long = try #require(AccessoryDevice(address: "aa-bb-cc-dd-ee-ff", name: String(repeating: "a", count: 120), majorClass: 4, minorClass: 6))
        #expect(long.name.utf8.count == 80)
        // 41 two-byte characters are 82 bytes; the cut falls inside the 41st, which goes whole.
        let accents = try #require(AccessoryDevice(address: "aa-bb-cc-dd-ee-ff", name: String(repeating: "é", count: 41), majorClass: 4, minorClass: 6))
        #expect(accents.name == String(repeating: "é", count: 40))
        let empty = try #require(AccessoryDevice(address: "AA:BB:CC:DD:EE:FF", name: "   ", majorClass: 4, minorClass: 6))
        #expect(empty.name == "aa-bb-cc-dd-ee-ff")
    }
}
