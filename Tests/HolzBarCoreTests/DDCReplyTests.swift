import Testing
@testable import HolzBarCore

@Suite("DDCReply")
struct DDCReplyTests {
    /// Real replies of a Samsung S34C65xV, read over DDC/CI.
    private let brightness: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x32, 0x00, 0x0F, 0x99]

    /// A reply frame with the checksum a monitor would append.
    private func frame(_ body: [UInt8]) -> [UInt8] {
        body + [body.reduce(0x50, ^)]
    }

    @Test("A valid reply gives the current and the maximum value, big endian")
    func values() {
        #expect(DDCReply.parse(brightness, expecting: .brightness) == .value(current: 15, maximum: 50))
        let contrast: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x32, 0x00, 0x32, 0xA6]
        #expect(DDCReply.parse(contrast, expecting: .contrast) == .value(current: 50, maximum: 50))
        let volume: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x62, 0x00, 0x00, 0x64, 0x00, 0x31, 0x83]
        #expect(DDCReply.parse(volume, expecting: .volume) == .value(current: 49, maximum: 100))
        let mute: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x8D, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xC6]
        #expect(DDCReply.parse(mute, expecting: .mute) == .value(current: 0, maximum: 255))
    }

    @Test("A two-byte value uses both bytes")
    func wideValues() {
        let reply = frame([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x01, 0x2C, 0x00, 0xFA])
        #expect(DDCReply.parse(reply, expecting: .brightness) == .value(current: 250, maximum: 300))
    }

    @Test("A reply for a code that was not asked for is invalid, even the real unsupported answer")
    func otherCode() {
        let unsupported: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x99, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x2C]
        #expect(DDCReply.parse(unsupported, expecting: .brightness) == .invalid(.wrongCode))
        #expect(DDCReply.parse(brightness, expecting: .contrast) == .invalid(.wrongCode))
    }

    @Test("Result code 1 for the code asked is unsupported")
    func unsupportedResult() {
        let reply = frame([0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0xFF, 0xFF, 0x00, 0x00])
        #expect(DDCReply.parse(reply, expecting: .brightness) == .unsupported)
    }

    @Test("Any other result code is invalid")
    func otherResult() {
        let reply = frame([0x6E, 0x88, 0x02, 0x02, 0x10, 0x00, 0x00, 0x32, 0x00, 0x0F])
        #expect(DDCReply.parse(reply, expecting: .brightness) == .invalid(.resultCode))
    }

    @Test("A valid frame whose maximum is 0 is unsupported, not a range")
    func zeroMaximum() {
        let reply = frame([0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(DDCReply.parse(reply, expecting: .brightness) == .unsupported)
    }

    @Test("A null message is recognised by its length byte and the stale tail is never read")
    func nullMessage() {
        let stale: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0x10, 0x00, 0x00, 0x32, 0x00, 0x0F, 0x99]
        #expect(DDCReply.parse(stale, expecting: .brightness) == .nullMessage)
        #expect(DDCReply.parse([0x6E, 0x80, 0xBE], expecting: .brightness) == .nullMessage)
    }

    @Test("A flipped checksum is invalid")
    func checksum() {
        var reply = brightness
        reply[10] ^= 0xFF
        #expect(DDCReply.parse(reply, expecting: .brightness) == .invalid(.checksum))
        var flipped = brightness
        flipped[7] ^= 0x01
        #expect(DDCReply.parse(flipped, expecting: .brightness) == .invalid(.checksum))
    }

    @Test("A reply that is not a Get VCP reply is invalid")
    func opcode() {
        let notVCP = frame([0x6E, 0x88, 0x03, 0x00, 0x10, 0x00, 0x00, 0x32, 0x00, 0x0F])
        #expect(DDCReply.parse(notVCP, expecting: .brightness) == .invalid(.wrongOpcode))
        let shortVCP = frame([0x6E, 0x85, 0x02, 0x00, 0x10, 0x00, 0x32])
        #expect(DDCReply.parse(shortVCP, expecting: .brightness) == .invalid(.wrongOpcode))
    }

    @Test("A frame longer than the bytes read is invalid")
    func frameTooLong() {
        let reply = Array(brightness.prefix(8))
        #expect(DDCReply.parse(reply, expecting: .brightness) == .invalid(.frameTooLong))
    }

    @Test("A reply from another address, without the length flag, or without bytes is invalid")
    func framing() {
        var wrongAddress = brightness
        wrongAddress[0] = 0x6F
        #expect(DDCReply.parse(wrongAddress, expecting: .brightness) == .invalid(.wrongAddress))
        var noFlag = brightness
        noFlag[1] = 0x08
        #expect(DDCReply.parse(noFlag, expecting: .brightness) == .invalid(.wrongLengthByte))
        #expect(DDCReply.parse([UInt8](repeating: 0, count: 11), expecting: .brightness) == .invalid(.wrongAddress))
        #expect(DDCReply.parse([], expecting: .brightness) == .invalid(.tooShort))
        #expect(DDCReply.parse([0x6E, 0x88], expecting: .brightness) == .invalid(.tooShort))
    }
}
