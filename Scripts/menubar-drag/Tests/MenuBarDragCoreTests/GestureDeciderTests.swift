//
//  GestureDeciderTests.swift
//  holzBar
//

import CoreGraphics
import Testing

@testable import MenuBarDragCore

@Suite("GestureDecider")
struct GestureDeciderTests {
    private let barMaxY: CGFloat = 24
    private let press = CGPoint(x: 435, y: 12)

    private func holding() -> GestureDecider {
        var decider = GestureDecider()
        _ = decider.mouseDown(at: press, time: 1, onItem: true)
        return decider
    }

    @Test("a press and a release at the same point become one replayed click")
    func click() {
        var decider = GestureDecider()
        #expect(decider.mouseDown(at: press, time: 1, onItem: true) == .swallow)
        #expect(decider.heldSince == 1)
        #expect(decider.mouseUp(at: press, time: 1.1) == .replayClick(down: press, up: press))
        #expect(decider.state == .idle)
        #expect(decider.heldSince == nil)
    }

    @Test("a sideways move of 4 points or more becomes a Command-drag, later events are rewritten")
    func sidewaysDrag() {
        var decider = holding()
        #expect(decider.mouseDragged(to: CGPoint(x: 437, y: 12), time: 1.05, barMaxY: barMaxY) == .swallow)
        #expect(
            decider.mouseDragged(to: CGPoint(x: 440, y: 12), time: 1.06, barMaxY: barMaxY)
                == .replayCommandDown(at: press)
        )
        #expect(decider.mouseDragged(to: CGPoint(x: 470, y: 12), time: 1.07, barMaxY: barMaxY) == .rewriteWithCommand)
        #expect(decider.mouseUp(at: CGPoint(x: 480, y: 12), time: 1.2) == .rewriteWithCommand)
        #expect(decider.state == .idle)
    }

    @Test("a sideways move of exactly 4 points to the left counts as a drag")
    func leftwardThreshold() {
        var decider = holding()
        #expect(
            decider.mouseDragged(to: CGPoint(x: 431, y: 12), time: 1.05, barMaxY: barMaxY)
                == .replayCommandDown(at: press)
        )
    }

    @Test("leaving the bar downward replays a plain press and lets the rest through")
    func leavingTheBar() {
        var decider = holding()
        #expect(
            decider.mouseDragged(to: CGPoint(x: 436, y: 40), time: 1.05, barMaxY: barMaxY)
                == .replayPlainDown(at: press)
        )
        #expect(decider.state == .menuTracking)
        #expect(decider.mouseDragged(to: CGPoint(x: 500, y: 80), time: 1.1, barMaxY: barMaxY) == .pass)
        #expect(decider.mouseUp(at: CGPoint(x: 500, y: 80), time: 1.2) == .pass)
        #expect(decider.state == .idle)
    }

    @Test("a press that is not on an item and its drags and release pass")
    func notOnAnItem() {
        var decider = GestureDecider()
        #expect(decider.mouseDown(at: press, time: 1, onItem: false) == .pass)
        #expect(decider.mouseDragged(to: CGPoint(x: 500, y: 12), time: 1.1, barMaxY: barMaxY) == .pass)
        #expect(decider.mouseUp(at: CGPoint(x: 500, y: 12), time: 1.2) == .pass)
    }

    @Test("a jitter of 3 points before the release is still a click")
    func jitter() {
        var decider = holding()
        let moved = CGPoint(x: 438, y: 13)
        #expect(decider.mouseDragged(to: moved, time: 1.05, barMaxY: barMaxY) == .swallow)
        #expect(decider.mouseUp(at: moved, time: 1.1) == .replayClick(down: press, up: moved))
    }

    @Test("a second press while holding resets and holds the new point")
    func secondPress() {
        var decider = holding()
        let other = CGPoint(x: 600, y: 10)
        #expect(decider.mouseDown(at: other, time: 2, onItem: true) == .swallow)
        #expect(decider.heldSince == 2)
        #expect(decider.mouseUp(at: other, time: 2.1) == .replayClick(down: other, up: other))
    }
}
