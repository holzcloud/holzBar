import Testing
@testable import HolzBarCore

@Suite("SliderValue")
struct SliderValueTests {
    @Test("A fraction maps into the bounds")
    func fractionMapsIntoTheBounds() {
        #expect(SliderValue.value(atFraction: 0.5, in: 0...10, step: nil) == 5)
        #expect(SliderValue.value(atFraction: -0.5, in: 0...10, step: nil) == 0)
        #expect(SliderValue.value(atFraction: 1.5, in: 0...10, step: nil) == 10)
        #expect(SliderValue.value(atFraction: 0.5, in: -16...16, step: 2) == 0)
    }

    @Test("Values snap to the step")
    func valuesSnapToTheStep() {
        #expect(SliderValue.snapped(3.3, in: 0...10, step: 0.5) == 3.5)
        #expect(SliderValue.snapped(3.3, in: 0...10, step: nil) == 3.3)
        #expect(SliderValue.snapped(0.31, in: 0...1, step: 0.1) == 0.3)
        #expect(SliderValue.snapped(-3, in: -16...16, step: 2) == -2)
        #expect(SliderValue.snapped(12, in: 0...10, step: 1) == 10)
    }

    @Test("The fraction of a value")
    func fractionOfAValue() {
        #expect(SliderValue.fraction(of: 2.5, in: 0...10) == 0.25)
        #expect(SliderValue.fraction(of: 5, in: 5...5) == 0)
        #expect(SliderValue.fraction(of: 20, in: 0...10) == 1)
    }

    @Test("Arrow keys move by one step")
    func arrowKeysMoveByOneStep() {
        #expect(SliderValue.increment(3, by: 1, in: 0...10, step: 0.5) == 3.5)
        #expect(SliderValue.increment(3, by: -1, in: 0...10, step: 0.5) == 2.5)
        let unstepped = SliderValue.increment(3, by: 1, in: 0...10, step: nil)
        #expect(abs(unstepped - 3.1) < 1e-9)
        #expect(SliderValue.increment(10, by: 1, in: 0...10, step: 0.5) == 10)
        #expect(SliderValue.increment(0, by: -1, in: 0...10, step: 0.5) == 0)
    }
}
