import Testing
@testable import HolzBarCore

@Suite("DividerPlausibility")
struct DividerPlausibilityTests {
    private typealias Span = DividerPlausibility.Span

    private let clock = Span(minX: 900, maxX: 960)

    @Test("Both dividers left of the Clock are plausible")
    func leftOfTheClock() {
        let hidden = Span(minX: 100, maxX: 120)
        let alwaysHidden = Span(minX: 60, maxX: 80)
        #expect(DividerPlausibility.isPlausible(hidden: hidden, alwaysHidden: alwaysHidden, clock: clock))
        #expect(DividerPlausibility.isPlausible(hidden: hidden, alwaysHidden: nil, clock: clock))
    }

    @Test("The hidden divider right of the Clock is implausible")
    func hiddenRightOfTheClock() {
        let hidden = Span(minX: 970, maxX: 990)
        #expect(!DividerPlausibility.isPlausible(hidden: hidden, alwaysHidden: nil, clock: clock))
        let alwaysHidden = Span(minX: 60, maxX: 80)
        #expect(!DividerPlausibility.isPlausible(hidden: hidden, alwaysHidden: alwaysHidden, clock: clock))
    }

    @Test("The tolerance is 2 points past the Clock's left edge")
    func tolerance() {
        let inside = Span(minX: clock.minX - 18.5, maxX: clock.minX + 1.5)
        let outside = Span(minX: clock.minX - 17.5, maxX: clock.minX + 2.5)
        let edge = Span(minX: clock.minX - 18, maxX: clock.minX + DividerPlausibility.tolerance)
        #expect(DividerPlausibility.tolerance == 2)
        #expect(DividerPlausibility.isPlausible(hidden: inside, alwaysHidden: nil, clock: clock))
        #expect(DividerPlausibility.isPlausible(hidden: edge, alwaysHidden: nil, clock: clock))
        #expect(!DividerPlausibility.isPlausible(hidden: outside, alwaysHidden: nil, clock: clock))
    }

    @Test("Without a Clock the read is plausible, whatever the dividers read")
    func noClock() {
        let far = Span(minX: 5000, maxX: 5020)
        #expect(DividerPlausibility.isPlausible(hidden: far, alwaysHidden: nil, clock: nil))
        #expect(DividerPlausibility.isPlausible(hidden: far, alwaysHidden: far, clock: nil))
    }

    @Test("The always-hidden divider right of the Clock is implausible, even with the hidden one left of it")
    func alwaysHiddenRightOfTheClock() {
        let hidden = Span(minX: 100, maxX: 120)
        let alwaysHidden = Span(minX: 970, maxX: 990)
        #expect(!DividerPlausibility.isPlausible(hidden: hidden, alwaysHidden: alwaysHidden, clock: clock))
    }

    @Test("A swapped pair left of the Clock stays plausible, so its repair keeps running")
    func swappedPairIsPlausible() {
        let hidden = Span(minX: 60, maxX: 80)
        let alwaysHidden = Span(minX: 100, maxX: 120)
        #expect(DividerPlausibility.isPlausible(hidden: hidden, alwaysHidden: alwaysHidden, clock: clock))
    }
}
