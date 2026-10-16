import CoreGraphics
import Testing
@testable import HolzBarMacOS27Core

@Suite("NativeOverflowShelf27")
struct NativeOverflowShelf27Tests {
    // A 1800-point display with the notch over 790...1010. The expanded frames are constructed
    // from the public description; replace them with the probe's measurements.
    let reading = NativeOverflowReading27(state: .expanded, displayID: 1, notchSpan: 790...1010)

    private func frame(_ minX: CGFloat, width: CGFloat = 30) -> CGRect {
        CGRect(x: minX, y: 2, width: width, height: 24)
    }

    @Test("A drawn item left of the notch is omitted")
    func leftOfNotch() {
        #expect(reading.shelfOmits(itemFrame: frame(700), isDrawn: true, onDisplay: 1))
    }

    @Test("A drawn item 2 points under the notch's left edge is omitted")
    func slightlyUnderLeftEdge() {
        #expect(reading.shelfOmits(itemFrame: frame(762), isDrawn: true, onDisplay: 1))
    }

    @Test("A drawn item 2 points under the notch's right edge is omitted")
    func slightlyUnderRightEdge() {
        #expect(reading.shelfOmits(itemFrame: frame(1008), isDrawn: true, onDisplay: 1))
    }

    @Test("A drawn item 30 points under the notch is kept")
    func farUnderNotch() {
        #expect(!reading.shelfOmits(itemFrame: frame(780, width: 40), isDrawn: true, onDisplay: 1))
    }

    @Test("A drawn item wholly under the notch is kept")
    func whollyUnderNotch() {
        #expect(!reading.shelfOmits(itemFrame: frame(850), isDrawn: true, onDisplay: 1))
    }

    @Test("An item macOS does not draw is kept")
    func notDrawn() {
        #expect(!reading.shelfOmits(itemFrame: frame(700), isDrawn: false, onDisplay: 1))
    }

    @Test("A reading of another display is kept")
    func otherDisplay() {
        #expect(!reading.shelfOmits(itemFrame: frame(700), isDrawn: true, onDisplay: 2))
    }

    @Test("A reading without a notch span keeps the item")
    func noNotchSpan() {
        let noSpan = NativeOverflowReading27(state: .expanded, displayID: 1, notchSpan: nil)
        #expect(!noSpan.shelfOmits(itemFrame: frame(700), isDrawn: true, onDisplay: 1))
    }

    @Test("A frame 2 points wide is kept")
    func narrowFrame() {
        #expect(!reading.shelfOmits(itemFrame: frame(700, width: 2), isDrawn: true, onDisplay: 1))
    }

    @Test("Fail safe: no other state omits any item")
    func failSafe() {
        let frames = [frame(700), frame(762), frame(1008), frame(780, width: 40), frame(850)]
        for state in [NativeOverflowState27.none, .collapsed, .unknown] {
            let other = NativeOverflowReading27(state: state, displayID: 1, notchSpan: 790...1010)
            for itemFrame in frames {
                #expect(!other.shelfOmits(itemFrame: itemFrame, isDrawn: true, onDisplay: 1))
            }
        }
    }
}
