import CoreGraphics
import Testing
@testable import HolzBarMacOS27Core

@Suite("NativeOverflowState27")
struct NativeOverflowState27Tests {
    // Measured on macOS 27.0: a 14-inch built-in display, 790 points unobscured on each side,
    // and the overflow button beside the notch. The frames of the expanded state are
    // constructed from the public description; replace them with the probe's measurements.
    let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    let chevron = CGRect(x: 1030, y: 2, width: 17, height: 30)
    var notch: ClosedRange<CGFloat>? {
        StuckOverflow27.notchSpan(displayBounds: display, leftAreaWidth: 790, rightAreaWidth: 790)
    }

    private func frame(_ minX: CGFloat, width: CGFloat = 30) -> CGRect {
        CGRect(x: minX, y: 2, width: width, height: 24)
    }

    @Test("No control and items right of the notch only is none")
    func none() {
        let state = NativeOverflowState27.derive(chevronFrame: nil, itemFrames: [frame(1100), frame(1132)], notchSpan: notch)
        #expect(state == .none)
    }

    @Test("Items stacked on the control with nothing left of the notch is collapsed")
    func collapsed() {
        let state = NativeOverflowState27.derive(
            chevronFrame: chevron, itemFrames: [frame(1020), frame(1022), frame(1100)], notchSpan: notch
        )
        #expect(state == .collapsed)
    }

    @Test("Nothing on the control and items left of the notch is expanded")
    func expanded() {
        let state = NativeOverflowState27.derive(
            chevronFrame: chevron, itemFrames: [frame(700), frame(732), frame(1100)], notchSpan: notch
        )
        #expect(state == .expanded)
    }

    @Test("Stacked items and an item left of the notch disagree, so the state is unknown")
    func disagreement() {
        let state = NativeOverflowState27.derive(
            chevronFrame: chevron, itemFrames: [frame(1020), frame(1022), frame(700)], notchSpan: notch
        )
        #expect(state == .unknown)
    }

    @Test("A control with neither fact is unknown")
    func loneControl() {
        let state = NativeOverflowState27.derive(chevronFrame: chevron, itemFrames: [frame(1100), frame(1132)], notchSpan: notch)
        #expect(state == .unknown)
    }

    @Test("No control but an item left of the notch is unknown")
    func loneLeftItem() {
        let state = NativeOverflowState27.derive(chevronFrame: nil, itemFrames: [frame(700), frame(1100)], notchSpan: notch)
        #expect(state == .unknown)
    }

    @Test("Without a notch span only none and collapsed can be told")
    func withoutNotch() {
        #expect(NativeOverflowState27.derive(chevronFrame: nil, itemFrames: [frame(1100)], notchSpan: nil) == .none)
        #expect(NativeOverflowState27.derive(chevronFrame: chevron, itemFrames: [frame(1020)], notchSpan: nil) == .collapsed)
        #expect(NativeOverflowState27.derive(chevronFrame: chevron, itemFrames: [frame(700)], notchSpan: nil) == .unknown)
    }

    @Test("Narrow frames do not count")
    func narrowFrames() {
        let counted = NativeOverflowState27.derive(
            chevronFrame: chevron, itemFrames: [frame(1020, width: 2), frame(700)], notchSpan: notch
        )
        #expect(counted == .expanded)
        let ignored = NativeOverflowState27.derive(chevronFrame: chevron, itemFrames: [frame(700, width: 2)], notchSpan: notch)
        #expect(ignored == .unknown)
    }

    @Test("An item reaching 6 points past the notch's left edge is still left of it, one more is not")
    func tolerance() {
        let inside = NativeOverflowState27.derive(chevronFrame: chevron, itemFrames: [frame(766)], notchSpan: notch)
        #expect(inside == .expanded)
        let outside = NativeOverflowState27.derive(chevronFrame: chevron, itemFrames: [frame(767)], notchSpan: notch)
        #expect(outside == .unknown)
    }

    @Test("The raw values are the words the log and the diagnostics print")
    func rawValues() {
        #expect(NativeOverflowState27.none.rawValue == "none")
        #expect(NativeOverflowState27.collapsed.rawValue == "collapsed")
        #expect(NativeOverflowState27.expanded.rawValue == "expanded")
        #expect(NativeOverflowState27.unknown.rawValue == "unknown")
    }

    @Test("The unknown reading has no display and no notch span")
    func unknownReading() {
        #expect(NativeOverflowReading27.unknown.state == .unknown)
        #expect(NativeOverflowReading27.unknown.displayID == nil)
        #expect(NativeOverflowReading27.unknown.notchSpan == nil)
    }
}
