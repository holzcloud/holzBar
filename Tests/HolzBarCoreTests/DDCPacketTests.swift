import Testing
@testable import HolzBarCore

@Suite("DDCPacket")
struct DDCPacketTests {
    @Test("A Get VCP request carries the code and the checksum of the DDC/CI frame")
    func getRequests() {
        #expect(DDCPacket.getRequest(.brightness) == [0x82, 0x01, 0x10, 0xAC])
        #expect(DDCPacket.getRequest(.contrast) == [0x82, 0x01, 0x12, 0xAE])
        #expect(DDCPacket.getRequest(.volume) == [0x82, 0x01, 0x62, 0xDE])
        #expect(DDCPacket.getRequest(.mute) == [0x82, 0x01, 0x8D, 0x31])
    }

    @Test("A Set VCP request carries the code and the value, big endian, with the checksum")
    func setRequests() {
        #expect(DDCPacket.setRequest(.brightness, value: 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        #expect(DDCPacket.setRequest(.volume, value: 30) == [0x84, 0x03, 0x62, 0x00, 0x1E, 0xC4])
        #expect(DDCPacket.setRequest(.mute, value: 1) == [0x84, 0x03, 0x8D, 0x00, 0x01, 0x34])
        #expect(DDCPacket.setRequest(.mute, value: 2) == [0x84, 0x03, 0x8D, 0x00, 0x02, 0x37])
    }

    @Test("A value above 255 is sent in both bytes")
    func wideSetRequest() {
        let request = DDCPacket.setRequest(.contrast, value: 0x0123)
        #expect(request[3] == 0x01)
        #expect(request[4] == 0x23)
        #expect(request.count == 6)
    }

    @Test("Only brightness, contrast, volume and mute can be requested, never the input source")
    func onlyFourControls() {
        #expect(DDCControl.allCases.map(\.rawValue) == [0x10, 0x12, 0x62, 0x8D])
        #expect(DDCControl(rawValue: 0x60) == nil)
    }

    @Test("The addresses and the length of a reply are the DDC/CI ones")
    func constants() {
        #expect(DDCPacket.standardChipAddress == 0x37)
        #expect(DDCPacket.mcdpChipAddress == 0xB7)
        #expect(DDCPacket.dataAddress == 0x51)
        #expect(DDCPacket.getReplyLength == 11)
    }

    @Test("The timing is the one measured on a monitor that drops the first write")
    func timing() {
        #expect(DDCTiming.writeCycles == 2)
        #expect(DDCTiming.attempts == 5)
        #expect(DDCTiming.writeWait == 10_000)
        #expect(DDCTiming.readWait == 50_000)
        #expect(DDCTiming.retryWait == 20_000)
        #expect(DDCTiming.settle == .milliseconds(300))
    }
}
