import Foundation
import Testing
@testable import HolzBarCore

@Suite("HubScrollGesture")
struct HubScrollGestureTests {
    typealias Gesture = HubScrollGesture
    typealias Sample = HubScrollGesture.Sample

    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// A trackpad sample: precise deltas, with a phase.
    private func pad(
        dx: Double = 0,
        dy: Double = 0,
        inverted: Bool = false,
        phase: Gesture.Phase = .changed,
        momentum: Gesture.Phase = .none,
        at offset: TimeInterval = 0
    ) -> Sample {
        Sample(
            dx: dx,
            dy: dy,
            isPrecise: true,
            isInverted: inverted,
            phase: phase,
            momentumPhase: momentum,
            at: start.addingTimeInterval(offset)
        )
    }

    /// A mouse wheel sample: lines, no phase.
    private func wheel(dx: Double = 0, dy: Double = 0, inverted: Bool = false, at offset: TimeInterval = 0) -> Sample {
        Sample(
            dx: dx,
            dy: dy,
            isPrecise: false,
            isInverted: inverted,
            phase: .none,
            momentumPhase: .none,
            at: start.addingTimeInterval(offset)
        )
    }

    @Test("The thresholds are 20 points, one line and 400 ms")
    func constants() {
        #expect(Gesture.preciseThreshold == 20)
        #expect(Gesture.lineThreshold == 1)
        #expect(Gesture.coolDown == 0.4)
    }

    @Test("A trackpad swipe down acts once when 20 points have accumulated, and not again until it ends")
    func swipeDownActsOnce() {
        var gesture = Gesture()
        #expect(gesture.offer(pad(dy: -8, phase: .began)) == nil)
        #expect(gesture.offer(pad(dy: -8)) == nil)
        #expect(gesture.offer(pad(dy: -8)) == .open)
        #expect(gesture.offer(pad(dy: -30)) == nil)
        #expect(gesture.offer(pad(dy: -30)) == nil)
        #expect(gesture.offer(pad(phase: .ended)) == nil)
        // The next gesture, up, closes at once: a gesture has no cool-down.
        #expect(gesture.offer(pad(dy: 25, phase: .began)) == .close)
    }

    @Test("With natural scrolling the same finger movement gives the opposite sign")
    func invertedDirection() {
        var natural = Gesture()
        #expect(natural.offer(pad(dy: 21, inverted: true, phase: .began)) == .open)
        var natural2 = Gesture()
        #expect(natural2.offer(pad(dy: -21, inverted: true, phase: .began)) == .close)
        var classic = Gesture()
        #expect(classic.offer(pad(dy: 21, phase: .began)) == .close)
    }

    @Test("Exactly 20 points act and 19.99 do not")
    func boundary() {
        var exact = Gesture()
        #expect(exact.offer(pad(dy: -20, phase: .began)) == .open)
        var below = Gesture()
        #expect(below.offer(pad(dy: -19.99, phase: .began)) == nil)
        #expect(below.offer(pad(dy: -0.02)) == .open)
        var short = Gesture()
        #expect(short.offer(pad(dy: -19.99, phase: .began)) == nil)
        #expect(short.offer(pad(dy: 0)) == nil)
        #expect(short.offer(pad(phase: .ended)) == nil)
    }

    @Test("A momentum sample never acts, whatever its size")
    func momentumNeverActs() {
        var gesture = Gesture()
        for phase in [Gesture.Phase.began, .changed, .ended] {
            #expect(gesture.offer(pad(dy: -500, phase: .none, momentum: phase)) == nil)
            #expect(gesture.offer(pad(dx: 500, phase: .none, momentum: phase)) == nil)
        }
        // A real swipe still acts afterwards.
        #expect(gesture.offer(pad(dy: -25, phase: .began)) == .open)
        // And its tail does not.
        #expect(gesture.offer(pad(phase: .ended)) == nil)
        #expect(gesture.offer(pad(dy: -80, phase: .none, momentum: .began)) == nil)
    }

    @Test("A cancelled gesture is over, like an ended one")
    func cancelledEnds() {
        var gesture = Gesture()
        #expect(gesture.offer(pad(dy: -25, phase: .began)) == .open)
        #expect(gesture.offer(pad(phase: .cancelled)) == nil)
        #expect(gesture.offer(pad(dy: -25, phase: .began)) == .open)
    }

    @Test("A sideways swipe skips: toward the left next, toward the right previous")
    func horizontal() {
        var left = Gesture()
        #expect(left.offer(pad(dx: 25, phase: .began)) == .next)
        var right = Gesture()
        #expect(right.offer(pad(dx: -25, phase: .began)) == .previous)
        var naturalLeft = Gesture()
        #expect(naturalLeft.offer(pad(dx: -25, inverted: true, phase: .began)) == .next)
        var naturalRight = Gesture()
        #expect(naturalRight.offer(pad(dx: 25, inverted: true, phase: .began)) == .previous)
    }

    @Test("The dominant axis decides, and a tie is vertical")
    func dominantAxis() {
        var mostlyVertical = Gesture()
        #expect(mostlyVertical.offer(pad(dx: 10, dy: -30, phase: .began)) == .open)
        var mostlyHorizontal = Gesture()
        #expect(mostlyHorizontal.offer(pad(dx: 30, dy: -10, phase: .began)) == .next)
        var tie = Gesture()
        #expect(tie.offer(pad(dx: 25, dy: -25, phase: .began)) == .open)
        // A small wobble on the other axis does not cancel the dominant one.
        var wobble = Gesture()
        #expect(wobble.offer(pad(dx: 12, dy: -10, phase: .began)) == nil)
        #expect(wobble.offer(pad(dx: 12, dy: -12)) == .next)
    }

    @Test("A gesture that never began still starts from its first sample")
    func firstSampleStarts() {
        var gesture = Gesture()
        #expect(gesture.offer(pad(dy: -12, phase: .changed)) == nil)
        #expect(gesture.offer(pad(dy: -12, phase: .changed)) == .open)
    }

    @Test("A mouse wheel acts on one line, then waits 400 ms")
    func wheelCoolDown() {
        var gesture = Gesture()
        #expect(gesture.offer(wheel(dy: -1, at: 0)) == .open)
        #expect(gesture.offer(wheel(dy: -1, at: 0.3)) == nil)
        #expect(gesture.offer(wheel(dy: -1, at: 0.39)) == nil)
        #expect(gesture.offer(wheel(dy: -1, at: 0.4)) == .open)
        // Half a line is not a notch.
        #expect(gesture.offer(wheel(dy: -0.5, at: 1.0)) == nil)
        // A refused sample does not extend the cool-down.
        #expect(gesture.offer(wheel(dy: 1, at: 1.2)) == .close)
    }

    @Test("A mouse wheel's sign is corrected too, and a sideways wheel skips")
    func wheelDirection() {
        var natural = Gesture()
        #expect(natural.offer(wheel(dy: 1, inverted: true, at: 0)) == .open)
        var classic = Gesture()
        #expect(classic.offer(wheel(dy: 1, at: 0)) == .close)
        var sideways = Gesture()
        #expect(sideways.offer(wheel(dx: 1, at: 0)) == .next)
        #expect(sideways.offer(wheel(dx: -1, at: 0.4)) == .previous)
    }

    @Test("reset clears an accumulated gesture and the cool-down")
    func resetClears() {
        var gesture = Gesture()
        #expect(gesture.offer(pad(dy: -15, phase: .began)) == nil)
        gesture.reset()
        #expect(gesture.offer(pad(dy: -15)) == nil)
        #expect(gesture.offer(pad(dy: -15)) == .open)
        gesture.reset()
        var wheelGesture = Gesture()
        #expect(wheelGesture.offer(wheel(dy: -1, at: 0)) == .open)
        wheelGesture.reset()
        #expect(wheelGesture.offer(wheel(dy: -1, at: 0.1)) == .open)
    }

    @Test("A precise device without phases acts at 20 points and then waits for the cool-down")
    func phaselessPrecise() {
        var gesture = Gesture()
        #expect(gesture.offer(pad(dy: -12, phase: .none, at: 0)) == nil)
        #expect(gesture.offer(pad(dy: -12, phase: .none, at: 0.01)) == .open)
        #expect(gesture.offer(pad(dy: -30, phase: .none, at: 0.1)) == nil)
        #expect(gesture.offer(pad(dy: -30, phase: .none, at: 0.5)) == .open)
        // A pause longer than the cool-down starts a new accumulation.
        var paused = Gesture()
        #expect(paused.offer(pad(dy: -12, phase: .none, at: 0)) == nil)
        #expect(paused.offer(pad(dy: -12, phase: .none, at: 1)) == nil)
    }

    @Test("The area is the closed shape's span over the top row, never lower than the menu bar")
    func area() {
        typealias Rect = NotchHubGeometry.Rect
        // A notch: its own rectangle.
        let notch = Rect(x: 600, y: 0, width: 200, height: 32)
        #expect(Gesture.area(of: notch, menuBarHeight: 32) == notch)
        // No notch: the seed is a flat strip, the area gets the menu bar's height.
        let strip = Rect(x: 650, y: 0, width: 200, height: 0)
        #expect(Gesture.area(of: strip, menuBarHeight: 24) == Rect(x: 650, y: 0, width: 200, height: 24))
        // Apple's Dynamic Island: the seed lies below it, the area starts at the top edge.
        let island = Rect(x: 650, y: 44, width: 200, height: 0)
        #expect(Gesture.area(of: island, menuBarHeight: 38) == Rect(x: 650, y: 0, width: 200, height: 38))
        // A menu bar height that makes no sense leaves the seed's own height.
        #expect(Gesture.area(of: notch, menuBarHeight: .nan).height == 32)
        #expect(Gesture.area(of: strip, menuBarHeight: -4).height == 0)
        // A point just below the menu bar is outside, the top edge is inside.
        let area = Gesture.area(of: strip, menuBarHeight: 24)
        #expect(area.contains(x: 700, y: 0))
        #expect(area.contains(x: 700, y: 24))
        #expect(!area.contains(x: 700, y: 24.5))
        #expect(!area.contains(x: 649, y: 10))
    }

    @Test("The gesture flash lasts one second, shorter than an indicator's hold")
    func flashSeconds() {
        #expect(Gesture.flashSeconds == 1)
        #expect(Gesture.flashSeconds < DesignTokens.Indicator.holdSeconds)
    }
}
