#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import HolzBarCore

@Suite("MenuBarDragDecider")
struct MenuBarDragDeciderTests {
    private let barMaxY: CGFloat = 24
    private let press = CGPoint(x: 435, y: 12)

    private func holding() -> MenuBarDragDecider {
        var decider = MenuBarDragDecider()
        _ = decider.mouseDown(at: press, time: 1, onItem: true)
        return decider
    }

    @Test("A press and a release at the same point become one replayed click")
    func click() {
        var decider = MenuBarDragDecider()
        #expect(decider.mouseDown(at: press, time: 1, onItem: true) == .swallow)
        #expect(decider.heldSince == 1)
        #expect(decider.mouseUp(at: press, time: 1.1) == .replayClick(down: press, up: press))
        #expect(decider.state == .idle)
        #expect(decider.heldSince == nil)
    }

    @Test("A sideways move of 4 points or more becomes a Command-drag, later events are rewritten")
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

    @Test("A sideways move of exactly 4 points to the left counts as a drag")
    func leftwardThreshold() {
        var decider = holding()
        #expect(
            decider.mouseDragged(to: CGPoint(x: 431, y: 12), time: 1.05, barMaxY: barMaxY)
                == .replayCommandDown(at: press)
        )
    }

    @Test("Leaving the bar downward replays a plain press and lets the rest through")
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

    @Test("A press that moves straight down into the Shelf's zone becomes a drag")
    func straightDownIntoTheShelf() {
        var decider = holding()
        let zone = CGRect(x: 300, y: 24, width: 300, height: 300)
        #expect(
            decider.mouseDragged(to: CGPoint(x: 436, y: 60), time: 1.05, barMaxY: barMaxY, shelfZone: zone)
                == .replayCommandDown(at: press)
        )
        #expect(decider.state == .dragging)
        #expect(
            decider.mouseDragged(to: CGPoint(x: 440, y: 90), time: 1.1, barMaxY: barMaxY, shelfZone: zone)
                == .rewriteWithCommand
        )
        #expect(decider.mouseUp(at: CGPoint(x: 440, y: 90), time: 1.2) == .rewriteWithCommand)
    }

    @Test("A move down outside the Shelf's zone, or without a zone, still tracks the menu")
    func downOutsideTheShelf() {
        let zone = CGRect(x: 600, y: 24, width: 300, height: 300)
        var outside = holding()
        #expect(
            outside.mouseDragged(to: CGPoint(x: 436, y: 60), time: 1.05, barMaxY: barMaxY, shelfZone: zone)
                == .replayPlainDown(at: press)
        )
        #expect(outside.state == .menuTracking)
        var withoutZone = holding()
        #expect(
            withoutZone.mouseDragged(to: CGPoint(x: 436, y: 60), time: 1.05, barMaxY: barMaxY)
                == .replayPlainDown(at: press)
        )
    }

    @Test("A sideways move is a drag whether or not a zone is given")
    func sidewaysWithAZone() {
        var decider = holding()
        let zone = CGRect(x: 600, y: 24, width: 300, height: 300)
        #expect(
            decider.mouseDragged(to: CGPoint(x: 440, y: 12), time: 1.05, barMaxY: barMaxY, shelfZone: zone)
                == .replayCommandDown(at: press)
        )
    }

    @Test("A press that is not on an item and its drags and release pass")
    func notOnAnItem() {
        var decider = MenuBarDragDecider()
        #expect(decider.mouseDown(at: press, time: 1, onItem: false) == .pass)
        #expect(decider.mouseDragged(to: CGPoint(x: 500, y: 12), time: 1.1, barMaxY: barMaxY) == .pass)
        #expect(decider.mouseUp(at: CGPoint(x: 500, y: 12), time: 1.2) == .pass)
    }

    @Test("A jitter of 3 points before the release is still a click")
    func jitter() {
        var decider = holding()
        let moved = CGPoint(x: 438, y: 13)
        #expect(decider.mouseDragged(to: moved, time: 1.05, barMaxY: barMaxY) == .swallow)
        #expect(decider.mouseUp(at: moved, time: 1.1) == .replayClick(down: press, up: moved))
    }

    @Test("A second press while holding resets and holds the new point")
    func secondPress() {
        var decider = holding()
        let other = CGPoint(x: 600, y: 10)
        #expect(decider.mouseDown(at: other, time: 2, onItem: true) == .swallow)
        #expect(decider.heldSince == 2)
        #expect(decider.mouseUp(at: other, time: 2.1) == .replayClick(down: other, up: other))
    }

    @Test("Resetting while holding goes back to idle and forgets the held press")
    func reset() {
        var decider = holding()
        #expect(decider.heldSince == 1)
        decider.reset()
        #expect(decider.state == .idle)
        #expect(decider.heldSince == nil)
        #expect(decider.mouseUp(at: press, time: 1.1) == .pass)
    }
}

@Suite("MenuBarDragPress")
struct MenuBarDragPressTests {
    /// A plain single press on an app item of a shown bar that the user made.
    private let plain = MenuBarDragPress(
        isOnAppItem: true,
        isBarShown: true,
        isHandlingDrop: false,
        isPostedByHolzBar: false,
        hasCommand: false,
        hasControl: false,
        hasOption: false,
        clickCount: 1
    )

    @Test("A plain single press on an app item of a shown bar is held")
    func plainPress() {
        #expect(plain.isHeld)
    }

    @Test("A press with Command is not held")
    func command() {
        var press = plain
        press.hasCommand = true
        #expect(!press.isHeld)
    }

    @Test("A press with Control is not held")
    func control() {
        var press = plain
        press.hasControl = true
        #expect(!press.isHeld)
    }

    @Test("A press with Option is not held")
    func option() {
        var press = plain
        press.hasOption = true
        #expect(!press.isHeld)
    }

    @Test("The second and the third press of a multiple click are not held")
    func multipleClicks() {
        var press = plain
        press.clickCount = 2
        #expect(!press.isHeld)
        press.clickCount = 3
        #expect(!press.isHeld)
    }

    @Test("An event without a click count is held")
    func noClickCount() {
        var press = plain
        press.clickCount = 0
        #expect(press.isHeld)
    }

    @Test("A press that holzBar posted is not held")
    func postedByHolzBar() {
        var press = plain
        press.isPostedByHolzBar = true
        #expect(!press.isHeld)
    }

    @Test("A press that is not on an app item is not held")
    func notOnAnAppItem() {
        var press = plain
        press.isOnAppItem = false
        #expect(!press.isHeld)
    }

    @Test("A press while the bar is not shown is not held")
    func barNotShown() {
        var press = plain
        press.isBarShown = false
        #expect(!press.isHeld)
    }

    @Test("A press while a drop is handled is not held")
    func handlingDrop() {
        var press = plain
        press.isHandlingDrop = true
        #expect(!press.isHeld)
    }
}
