import Testing
@testable import HolzBarCore

@Suite("DDCRegistryPairing")
struct DDCRegistryPairingTests {
    typealias Proxy = DDCRegistryPairing.Proxy

    // MARK: Slot of a name

    @Test("The number after ext is the slot, in either case and without leading zeros")
    func slotOfNames() {
        #expect(DDCRegistryPairing.slot(in: "dispext0") == "ext0")
        #expect(DDCRegistryPairing.slot(in: "dcpext1") == "ext1")
        #expect(DDCRegistryPairing.slot(in: "dispext2:dcpav-service-epic:0") == "ext2")
        #expect(DDCRegistryPairing.slot(in: "DCPEXT0Endpoint1") == "ext0")
        #expect(DDCRegistryPairing.slot(in: "iop-dcpext10-nub") == "ext10")
        #expect(DDCRegistryPairing.slot(in: "dispext007") == "ext7")
    }

    @Test("A name without ext followed by a digit has no slot")
    func namesWithoutSlot() {
        #expect(DDCRegistryPairing.slot(in: "") == nil)
        #expect(DDCRegistryPairing.slot(in: "disp0") == nil)
        #expect(DDCRegistryPairing.slot(in: "AppleCLCD2") == nil)
        #expect(DDCRegistryPairing.slot(in: "AFKEPInterfaceServiceKextV2") == nil)
        #expect(DDCRegistryPairing.slot(in: "ext") == nil)
        #expect(DDCRegistryPairing.slot(in: "dispext") == nil)
        #expect(DDCRegistryPairing.slot(in: "DCPAVServiceProxy") == nil)
    }

    @Test("A very long run of digits cannot overflow")
    func hugeNumber() {
        let name = "ext" + String(repeating: "9", count: 80)
        #expect(DDCRegistryPairing.slot(in: name) != nil)
    }

    // MARK: Pairing by slot

    @Test("Each proxy takes the framebuffer with its slot, whatever the walk order")
    func pairsBySlot() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: ["ext1", "ext0"],
            proxies: [
                Proxy(slot: "ext0", previousFramebuffer: 0),
                Proxy(slot: "ext1", previousFramebuffer: 1)
            ]
        )
        #expect(result == [1, 0])
    }

    @Test("A proxy whose own framebuffer is missing does not take the one walked before it")
    func missingFramebufferIsNotReplacedByWalkOrder() {
        // [fbA(ext0), proxyB(ext1), fbB(ext1)] is paired by slot; and with fbB gone, proxyB gets nothing.
        let withBoth = DDCRegistryPairing.pair(
            framebufferSlots: ["ext0", "ext1"],
            proxies: [Proxy(slot: "ext1", previousFramebuffer: 0)]
        )
        #expect(withBoth == [1])
        let withoutB = DDCRegistryPairing.pair(
            framebufferSlots: ["ext0"],
            proxies: [Proxy(slot: "ext1", previousFramebuffer: 0)]
        )
        #expect(withoutB == [nil])
    }

    @Test("Two framebuffers with the same slot pair with no proxy")
    func duplicateFramebufferSlots() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: ["ext0", "ext0"],
            proxies: [Proxy(slot: "ext0", previousFramebuffer: 1)]
        )
        #expect(result == [nil])
    }

    @Test("A framebuffer that two proxies claim serves neither")
    func twoProxiesOneFramebuffer() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: ["ext0"],
            proxies: [
                Proxy(slot: "ext0", previousFramebuffer: 0),
                Proxy(slot: "ext0", previousFramebuffer: 0)
            ]
        )
        #expect(result == [nil, nil])
    }

    // MARK: Walk order only where no slot is named

    @Test("A proxy with no slot takes the framebuffer the walk passed last")
    func fallsBackToWalkOrder() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: [nil, nil],
            proxies: [
                Proxy(slot: nil, previousFramebuffer: 0),
                Proxy(slot: nil, previousFramebuffer: 1)
            ]
        )
        #expect(result == [0, 1])
    }

    @Test("Two proxies with no slot after the same framebuffer pair with neither")
    func unslottedProxiesSharingAFramebuffer() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: [nil],
            proxies: [
                Proxy(slot: nil, previousFramebuffer: 0),
                Proxy(slot: nil, previousFramebuffer: 0)
            ]
        )
        #expect(result == [nil, nil])
    }

    @Test("A proxy with no slot and no framebuffer before it pairs with nothing")
    func noFramebufferBefore() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: [nil],
            proxies: [Proxy(slot: nil, previousFramebuffer: nil)]
        )
        #expect(result == [nil])
    }

    @Test("A walk-order claim on a framebuffer that a slot already pairs serves neither proxy")
    func slotAndWalkOrderCollide() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: ["ext0"],
            proxies: [
                Proxy(slot: "ext0", previousFramebuffer: 0),
                Proxy(slot: nil, previousFramebuffer: 0)
            ]
        )
        #expect(result == [nil, nil])
    }

    @Test("A previous framebuffer that does not exist pairs with nothing")
    func invalidIndex() {
        let result = DDCRegistryPairing.pair(
            framebufferSlots: ["ext0"],
            proxies: [Proxy(slot: nil, previousFramebuffer: 5)]
        )
        #expect(result == [nil])
    }
}
