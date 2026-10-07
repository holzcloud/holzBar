import CoreGraphics
import Testing
@testable import HolzBarMacOS27Core

@Suite("ItemFrame27")
struct ItemFrame27Tests {
    @Test("A frame on the bar is kept")
    func valid() {
        let frame = ItemFrame27.validated(origin: CGPoint(x: 1242, y: 7.5), size: CGSize(width: 34, height: 24))
        #expect(frame == CGRect(x: 1242, y: 7.5, width: 34, height: 24))
        #expect(ItemFrame27.validated(origin: CGPoint(x: -1800, y: 0), size: .zero) == CGRect(x: -1800, y: 0, width: 0, height: 0))
    }

    @Test("Non-finite values are rejected")
    func nonFinite() {
        #expect(ItemFrame27.validated(origin: CGPoint(x: CGFloat.nan, y: 0), size: CGSize(width: 34, height: 24)) == nil)
        #expect(ItemFrame27.validated(origin: CGPoint(x: 0, y: CGFloat.infinity), size: CGSize(width: 34, height: 24)) == nil)
        #expect(ItemFrame27.validated(origin: .zero, size: CGSize(width: -CGFloat.infinity, height: 24)) == nil)
        #expect(ItemFrame27.validated(origin: .zero, size: CGSize(width: 34, height: CGFloat.nan)) == nil)
    }

    @Test("Huge values and negative sizes are rejected")
    func outOfRange() {
        #expect(ItemFrame27.validated(origin: CGPoint(x: 1e300, y: 0), size: CGSize(width: 34, height: 24)) == nil)
        #expect(ItemFrame27.validated(origin: CGPoint(x: -1e7, y: 0), size: CGSize(width: 34, height: 24)) == nil)
        #expect(ItemFrame27.validated(origin: .zero, size: CGSize(width: 1e6, height: 24)) == nil)
        #expect(ItemFrame27.validated(origin: .zero, size: CGSize(width: -1, height: 24)) == nil)
    }
}
