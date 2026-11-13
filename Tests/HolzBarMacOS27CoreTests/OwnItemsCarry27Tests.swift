import Testing
@testable import HolzBarMacOS27Core

@Suite("OwnItemsCarry27")
struct OwnItemsCarry27Tests {
    @Test("A read without holzBar's own bar keeps the items of the last read")
    func missingBarCarries() {
        #expect(OwnItemsCarry27.carriesLastRead(barReturned: false, lastReadItemCount: 3))
    }

    @Test("A read that returns the bar replaces the last read, even when it is empty")
    func returnedBarReplaces() {
        #expect(!OwnItemsCarry27.carriesLastRead(barReturned: true, lastReadItemCount: 3))
    }

    @Test("Nothing is carried before a read found holzBar's items")
    func nothingToCarry() {
        #expect(!OwnItemsCarry27.carriesLastRead(barReturned: false, lastReadItemCount: 0))
    }
}
