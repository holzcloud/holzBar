import Testing
@testable import HolzBarCore

@Suite("FileDragWatch")
struct FileDragWatchTests {
    typealias Watch = FileDragWatch

    /// A press at change count 7, as the first event of a drag.
    private func pressed(at count: Int = 7) -> Watch {
        var watch = Watch(changeCount: 1)
        watch.pressed(changeCount: count)
        return watch
    }

    /// Feeds one drag event the way the controller does: the pasteboard is inspected only when
    /// the watch asks for it.
    private func drag(
        _ watch: inout Watch,
        count: Int,
        hasFileURLs: Bool,
        inZone: Bool = false,
        inHub: Bool = false,
        hubIsOpen: Bool = false
    ) -> Watch.Outcome {
        watch.dragged(
            changeCount: count,
            hasFileURLs: hasFileURLs,
            pointerInZone: inZone,
            pointerInHub: inHub,
            hubIsOpen: hubIsOpen
        )
    }

    @Test("A new drag with file URLs and the pointer in the zone asks for the hub to open")
    func fileDragInZoneOpens() {
        var watch = pressed()
        #expect(watch.needsInspection(changeCount: 8))
        let outcome = drag(&watch, count: 8, hasFileURLs: true, inZone: true)
        #expect(outcome == Watch.Outcome(wish: .open, showDropTab: false))
    }

    @Test("A plain mouse drag never needs inspecting and never asks for anything")
    func plainDragDoesNothing() {
        var watch = pressed()
        #expect(!watch.needsInspection(changeCount: 7))
        // Even if the caller wrongly passed file URLs, an unchanged count is not a new drag.
        let inZone = drag(&watch, count: 7, hasFileURLs: true, inZone: true)
        #expect(inZone == Watch.Outcome(wish: nil, showDropTab: false))
        let away = drag(&watch, count: 7, hasFileURLs: true)
        #expect(away == Watch.Outcome(wish: nil, showDropTab: false))
        #expect(!watch.isFileDrag)
    }

    @Test("A drag without file URLs is inspected once and never asks for anything")
    func textDragDoesNothing() {
        var watch = pressed()
        let first = drag(&watch, count: 8, hasFileURLs: false, inZone: true)
        #expect(first == Watch.Outcome(wish: nil, showDropTab: false))
        #expect(!watch.needsInspection(changeCount: 8))
        let second = drag(&watch, count: 8, hasFileURLs: true, inZone: true)
        #expect(second == Watch.Outcome(wish: nil, showDropTab: false))
    }

    @Test("After a press, a new file drag with a new count asks for the hub to open")
    func nextPressStartsAgain() {
        var watch = pressed()
        _ = drag(&watch, count: 8, hasFileURLs: false)
        watch.pressed(changeCount: 8)
        #expect(watch.needsInspection(changeCount: 9))
        let outcome = drag(&watch, count: 9, hasFileURLs: true, inZone: true)
        #expect(outcome.wish == .open)
    }

    @Test("A file drag whose pointer leaves the zone before the hub opened asks for nothing")
    func leavingTheZoneWithdrawsTheWish() {
        var watch = pressed()
        #expect(drag(&watch, count: 8, hasFileURLs: true, inZone: true).wish == .open)
        let outside = drag(&watch, count: 8, hasFileURLs: true)
        #expect(outside == Watch.Outcome(wish: nil, showDropTab: false))
        // The policy turns that into cancelling the pending open.
        #expect(NotchHubPolicy.decision(desired: outside.wish, pending: .open) == .cancelPending)
    }

    @Test("A file drag over the open hub shows the drop tab, and outside it the hub is left open")
    func dragInsideAndOutsideTheOpenHub() {
        var watch = pressed()
        let inside = drag(&watch, count: 8, hasFileURLs: true, inHub: true, hubIsOpen: true)
        #expect(inside == Watch.Outcome(wish: nil, showDropTab: true))
        let outside = drag(&watch, count: 8, hasFileURLs: true, hubIsOpen: true)
        #expect(outside == Watch.Outcome(wish: nil, showDropTab: false))
        // The zone does not ask to open a hub that is already open.
        let zone = drag(&watch, count: 8, hasFileURLs: true, inZone: true, hubIsOpen: true)
        #expect(zone == Watch.Outcome(wish: nil, showDropTab: false))
    }

    @Test("Releasing outside a hub the drag opened asks for it to close")
    func releaseOutsideClosesDragOpenedHub() {
        var watch = pressed()
        _ = drag(&watch, count: 8, hasFileURLs: true, inZone: true)
        watch.hubOpened(byDrag: true)
        let outcome = watch.released(hubIsOpen: true, pointerInHub: false)
        #expect(outcome == Watch.Outcome(wish: .close, showDropTab: false))
        #expect(!watch.isFileDrag)
        #expect(!watch.needsInspection(changeCount: 7))
    }

    @Test("Releasing inside a hub the drag opened asks for nothing")
    func releaseInsideKeepsDragOpenedHub() {
        var watch = pressed()
        _ = drag(&watch, count: 8, hasFileURLs: true, inZone: true)
        watch.hubOpened(byDrag: true)
        let outcome = watch.released(hubIsOpen: true, pointerInHub: true)
        #expect(outcome == Watch.Outcome(wish: nil, showDropTab: false))
    }

    @Test("Releasing never closes a hub that hover or the hotkey opened, or one that is closed")
    func releaseLeavesOtherHubsAlone() {
        var byHover = pressed()
        _ = drag(&byHover, count: 8, hasFileURLs: true, inHub: true, hubIsOpen: true)
        byHover.hubOpened(byDrag: false)
        #expect(byHover.released(hubIsOpen: true, pointerInHub: false).wish == nil)

        var closed = pressed()
        closed.hubOpened(byDrag: true)
        closed.hubClosed()
        #expect(closed.released(hubIsOpen: false, pointerInHub: false).wish == nil)

        var wrongState = pressed()
        wrongState.hubOpened(byDrag: true)
        #expect(wrongState.released(hubIsOpen: false, pointerInHub: false).wish == nil)
    }

    @Test("A stale file drag, whose drop never reported a release, is cleared by the next press")
    func stalePressResets() {
        var watch = pressed()
        _ = drag(&watch, count: 8, hasFileURLs: true, inZone: true)
        #expect(watch.isFileDrag)
        // The drop was in holzBar's own window: no mouse-up reached the global monitor.
        watch.pressed(changeCount: 10)
        #expect(!watch.isFileDrag)
        let plain = drag(&watch, count: 10, hasFileURLs: true, inZone: true)
        #expect(plain == Watch.Outcome(wish: nil, showDropTab: false))
    }

    @Test("While a file drag is known the pasteboard is not inspected again")
    func inspectedOncePerDrag() {
        var watch = pressed()
        #expect(watch.needsInspection(changeCount: 8))
        _ = drag(&watch, count: 8, hasFileURLs: true)
        #expect(!watch.needsInspection(changeCount: 8))
        #expect(!watch.needsInspection(changeCount: 9))
    }
}
