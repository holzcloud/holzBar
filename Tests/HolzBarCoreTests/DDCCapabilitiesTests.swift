import Testing
@testable import HolzBarCore

@Suite("DDCCapabilities")
struct DDCCapabilitiesTests {
    typealias Capabilities = DDCCapabilities

    /// The five frames a Samsung S34C65xV answered with, at offsets 0, 32, 64, 96 and 101.
    static let frames: [(offset: UInt16, bytes: [UInt8])] = [
        (0, [0x6E, 0xA3, 0xE3, 0x00, 0x00, 0x28, 0x70, 0x72, 0x6F, 0x74, 0x28, 0x6D, 0x6F, 0x6E, 0x69, 0x74, 0x6F, 0x72,
             0x29, 0x74, 0x79, 0x70, 0x65, 0x28, 0x6C, 0x63, 0x64, 0x29, 0x4D, 0x53, 0x74, 0x61, 0x72, 0x63, 0x6D, 0x64,
             0x73, 0x30]),
        (32, [0x6E, 0xA3, 0xE3, 0x00, 0x20, 0x28, 0x30, 0x31, 0x20, 0x30, 0x32, 0x20, 0x30, 0x33, 0x20, 0x30, 0x37, 0x20,
              0x30, 0x43, 0x20, 0x45, 0x33, 0x20, 0x46, 0x33, 0x29, 0x76, 0x63, 0x70, 0x28, 0x31, 0x30, 0x20, 0x31, 0x32,
              0x20, 0x67]),
        (64, [0x6E, 0xA3, 0xE3, 0x00, 0x40, 0x20, 0x44, 0x46, 0x20, 0x36, 0x32, 0x20, 0x38, 0x44, 0x20, 0x46, 0x44, 0x29,
              0x6D, 0x63, 0x63, 0x73, 0x5F, 0x76, 0x65, 0x72, 0x28, 0x32, 0x2E, 0x31, 0x29, 0x6D, 0x73, 0x77, 0x68, 0x71,
              0x6C, 0x7F]),
        (96, [0x6E, 0x88, 0xE3, 0x00, 0x60, 0x28, 0x31, 0x29, 0x29, 0x00, 0x2C]),
        (101, [0x6E, 0x83, 0xE3, 0x00, 0x65, 0x3B]),
    ]

    static let realText = "(prot(monitor)type(lcd)MStarcmds(01 02 03 07 0C E3 F3)vcp(10 12  DF 62 8D FD)mccs_ver(2.1)mswhql(1))"

    @Test("Each real fragment gives its own data bytes for its own offset")
    func realFragments() {
        let expectedCounts = [32, 32, 32, 5, 0]
        for (index, frame) in Self.frames.enumerated() {
            let data = Capabilities.fragment(frame.bytes, expectingOffset: frame.offset)
            #expect(data?.count == expectedCounts[index])
        }
        #expect(Capabilities.fragment(Self.frames[3].bytes, expectingOffset: 96) == [0x28, 0x31, 0x29, 0x29, 0x00])
    }

    @Test("A fragment is refused for any other offset than the one requested")
    func wrongOffset() {
        #expect(Capabilities.fragment(Self.frames[0].bytes, expectingOffset: 32) == nil)
        #expect(Capabilities.fragment(Self.frames[1].bytes, expectingOffset: 0) == nil)
        #expect(Capabilities.fragment(Self.frames[4].bytes, expectingOffset: 96) == nil)
    }

    @Test("A flipped checksum, another opcode or a wrong address is refused")
    func badFrames() {
        var flipped = Self.frames[0].bytes
        flipped[flipped.count - 1] ^= 0x01
        #expect(Capabilities.fragment(flipped, expectingOffset: 0) == nil)

        var otherOpcode = Self.frames[4].bytes
        otherOpcode[2] = 0x02
        otherOpcode[5] = 0x50 ^ otherOpcode[0..<5].reduce(0, ^)
        #expect(Capabilities.fragment(otherOpcode, expectingOffset: 101) == nil)

        var otherAddress = Self.frames[4].bytes
        otherAddress[0] = 0x6F
        otherAddress[5] = 0x50 ^ otherAddress[0..<5].reduce(0, ^)
        #expect(Capabilities.fragment(otherAddress, expectingOffset: 101) == nil)

        var noFlag = Self.frames[4].bytes
        noFlag[1] = 0x03
        noFlag[5] = 0x50 ^ noFlag[0..<5].reduce(0, ^)
        #expect(Capabilities.fragment(noFlag, expectingOffset: 101) == nil)
    }

    @Test("A length byte that does not fit the buffer, or is too small, is refused")
    func badLengths() {
        // Announces 35 bytes of payload but the buffer holds the 11 bytes of the last data fragment.
        var tooLong = Self.frames[3].bytes
        tooLong[1] = 0xA3
        #expect(Capabilities.fragment(tooLong, expectingOffset: 96) == nil)
        // A payload shorter than opcode and offset cannot be a fragment.
        var tooShort = [UInt8](Self.frames[4].bytes[0..<4])
        tooShort[1] = 0x82
        tooShort.append(0x50 ^ tooShort.reduce(0, ^))
        #expect(Capabilities.fragment(tooShort, expectingOffset: 0) == nil)
        #expect(Capabilities.fragment([], expectingOffset: 0) == nil)
        #expect(Capabilities.fragment([0x6E, 0x83, 0xE3], expectingOffset: 0) == nil)
        #expect(Capabilities.fragment([UInt8](repeating: 0, count: 38), expectingOffset: 0) == nil)
    }

    @Test("The assembler completes the real string once its parentheses balance")
    func assemblesRealString() {
        var assembler = Capabilities.Assembler()
        #expect(assembler.nextOffset == 0)
        for (index, frame) in Self.frames.prefix(4).enumerated() {
            #expect(!assembler.isComplete)
            #expect(assembler.nextOffset == frame.offset)
            let data = Capabilities.fragment(frame.bytes, expectingOffset: frame.offset) ?? []
            assembler.append(data)
            #expect(assembler.isComplete == (index == 3))
        }
        #expect(assembler.text == Self.realText)
        #expect(assembler.nextOffset == 101)
    }

    @Test("An empty fragment completes the assembler")
    func emptyFragmentCompletes() {
        var assembler = Capabilities.Assembler()
        assembler.append(Array("(vcp(10".utf8))
        #expect(!assembler.isComplete)
        assembler.append([])
        #expect(assembler.isComplete)
        #expect(assembler.text == "(vcp(10")
    }

    @Test("A string that never balances ends at the cap of 20 fragments, 640 bytes")
    func fragmentCap() {
        #expect(Capabilities.maximumFragments == 20)
        var assembler = Capabilities.Assembler()
        for count in 1...30 where !assembler.isComplete {
            assembler.append([UInt8](repeating: 0x28, count: 32))
            #expect(assembler.isComplete == (count == 20))
        }
        #expect(assembler.nextOffset == 640)
        assembler.append([UInt8](repeating: 0x28, count: 32))
        #expect(assembler.nextOffset == 640)
    }

    @Test("The text drops NUL bytes and bytes above 0x7F")
    func textIsAscii() {
        var assembler = Capabilities.Assembler()
        assembler.append([0x28, 0x61, 0x00, 0xFF, 0x62, 0x29, 0x00])
        #expect(assembler.text == "(ab)")
    }

    @Test("The vcp group of the real string lists six codes, vendor tokens ignored")
    func parsesRealString() {
        #expect(Capabilities.parse(Self.realText) == [0x10, 0x12, 0xDF, 0x62, 0x8D, 0xFD])
    }

    @Test("A code with sub-values keeps the code and skips the group, in either case")
    func parsesSubValues() {
        #expect(Capabilities.parse("(vcp(10 12 14(01 05 08 0B) 60(0F 11) 62 8d))") == [0x10, 0x12, 0x14, 0x60, 0x62, 0x8D])
        #expect(Capabilities.parse("(VCP(10 62))") == [0x10, 0x62])
    }

    @Test("vcp( is a token of its own: inside another name it is not the group, and the real group after it still is")
    func parsesTokenBoundary() {
        #expect(Capabilities.parse("(avcp(10 12))") == nil)
        #expect(Capabilities.parse("(x_vcp(10 12))") == nil)
        #expect(Capabilities.parse("(avcp(10 12)vcp(62 8D))") == [0x62, 0x8D])
        #expect(Capabilities.parse("vcp(10 62)") == [0x10, 0x62])
        #expect(Capabilities.parse("(cmds(01 02)vcp(10 62)mccs_ver(2.1))") == [0x10, 0x62])
        #expect(Capabilities.parse("(prot(monitor) vcp(10))") == [0x10])
    }

    @Test("No vcp group, an unbalanced one or an empty one gives nil so the fallback applies")
    func parseFailures() {
        #expect(Capabilities.parse("(prot(monitor)type(lcd))") == nil)
        #expect(Capabilities.parse("(vcp(10 12") == nil)
        #expect(Capabilities.parse("") == nil)
        #expect(Capabilities.parse("(vcp())") == nil)
        #expect(Capabilities.parse("(vcp(10 14(01 05)") == nil)
    }

    @Test("Only brightness, contrast, volume and mute are ever candidates")
    func candidates() {
        #expect(Capabilities.candidates(listed: nil) == nil)
        #expect(Capabilities.candidates(listed: [0x10, 0x12, 0xDF, 0x62, 0x8D, 0xFD]) == [.brightness, .contrast, .volume, .mute])
        #expect(Capabilities.candidates(listed: [0x10, 0x60]) == [.brightness])
        // The input source and every other code are dropped; with nothing left the fallback applies.
        #expect(Capabilities.candidates(listed: [0x60, 0xDF]) == nil)
        #expect(Capabilities.candidates(listed: []) == nil)
    }

    @Test("A card shows brightness, contrast and volume that were confirmed, mute only with volume")
    func rows() {
        #expect(Capabilities.rows(confirmed: [.brightness, .volume, .mute]) == [.brightness, .volume])
        #expect(Capabilities.rows(confirmed: [.mute, .contrast, .volume, .brightness]) == [.brightness, .contrast, .volume])
        #expect(Capabilities.rows(confirmed: [.mute]).isEmpty)
        #expect(Capabilities.rows(confirmed: []).isEmpty)
        #expect(!Capabilities.showsMute(confirmed: [.mute]))
        #expect(!Capabilities.showsMute(confirmed: [.volume]))
        #expect(Capabilities.showsMute(confirmed: [.volume, .mute]))
    }
}
