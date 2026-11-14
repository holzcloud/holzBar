import Testing
@testable import HolzBarCore

@Suite("HubIslandPhase")
struct HubIslandPhaseTests {
    typealias Phase = HubIslandPhase

    /// A state with the given values, to start a test from.
    private func state(
        _ target: Phase.Target,
        animating: Bool = false,
        generation: Int = 0,
        live: Bool = false
    ) -> Phase.State {
        Phase.State(target: target, isAnimating: animating, generation: generation, isLive: live)
    }

    @Test("Opening from closed starts an animation towards the open hub with generation 1")
    func openFromClosed() {
        let next = Phase.reduce(Phase.State(), .open)
        #expect(next.target == .open)
        #expect(next.isAnimating)
        #expect(next.generation == 1)
        #expect(next.isOpen)
        #expect(!next.hasShadow)
        #expect(next.isPanelVisible)
        #expect(next.showsContent)
        #expect(!next.ordersOut)
    }

    @Test("The open hub gets its shadow when its animation has finished, and opening twice changes nothing")
    func openSettles() {
        let opening = Phase.reduce(Phase.State(), .open)
        let settled = Phase.reduce(opening, .animationFinished(generation: 1))
        #expect(!settled.isAnimating)
        #expect(settled.hasShadow)
        #expect(settled.isOpen)
        #expect(Phase.reduce(settled, .open) == settled)
        // Also while it is still opening: no new generation.
        #expect(Phase.reduce(opening, .open) == opening)
    }

    @Test("Closing an open hub with nothing live returns to closed at once and orders the panel out when it finishes")
    func closeToClosed() {
        let open = state(.open, generation: 1)
        let closing = Phase.reduce(open, .close)
        #expect(closing.target == .closed)
        #expect(closing.isAnimating)
        #expect(closing.generation == 2)
        // From the first frame of closing the hub behaves as closed.
        #expect(!closing.isOpen)
        #expect(!closing.showsContent)
        #expect(!closing.hasShadow)
        #expect(closing.isPanelVisible)
        #expect(!closing.ordersOut)
        let closed = Phase.reduce(closing, .animationFinished(generation: 2))
        #expect(closed.ordersOut)
        #expect(!closed.isPanelVisible)
        #expect(!closed.isAnimating)
    }

    @Test("Closing while closed changes nothing")
    func closeWhileClosed() {
        let closed = Phase.State()
        #expect(Phase.reduce(closed, .close) == closed)
        let closing = state(.closed, animating: true, generation: 3)
        #expect(Phase.reduce(closing, .close) == closing)
    }

    @Test("Closing an open hub while something is live returns to the live state, which has no shadow and stays on screen")
    func closeToLive() {
        let open = state(.open, generation: 1, live: true)
        let closing = Phase.reduce(open, .close)
        #expect(closing.target == .live)
        #expect(closing.isAnimating)
        #expect(closing.generation == 2)
        #expect(!closing.isOpen)
        let live = Phase.reduce(closing, .animationFinished(generation: 2))
        #expect(live.showsLiveContent)
        #expect(!live.ordersOut)
        #expect(!live.hasShadow)
        #expect(live.isPanelVisible)
    }

    @Test("Opening during closing turns around; the old completion is ignored and the new one settles")
    func reopenDuringClosing() {
        let closing = Phase.reduce(state(.open, generation: 1), .close)
        let reopened = Phase.reduce(closing, .open)
        #expect(reopened.target == .open)
        #expect(reopened.isAnimating)
        #expect(reopened.generation == 3)
        #expect(reopened.isOpen)
        // The closing animation ends: it must not order the panel out.
        let stale = Phase.reduce(reopened, .animationFinished(generation: 2))
        #expect(stale == reopened)
        #expect(stale.isAnimating)
        #expect(!stale.ordersOut)
        #expect(stale.isPanelVisible)
        let settled = Phase.reduce(stale, .animationFinished(generation: 3))
        #expect(!settled.isAnimating)
        #expect(settled.hasShadow)
        #expect(!settled.ordersOut)
    }

    @Test("A completion that arrives twice, or for a generation that never ran, changes nothing")
    func strayCompletion() {
        let settled = Phase.reduce(Phase.reduce(Phase.State(), .open), .animationFinished(generation: 1))
        #expect(Phase.reduce(settled, .animationFinished(generation: 1)) == settled)
        #expect(Phase.reduce(settled, .animationFinished(generation: 9)) == settled)
        let opening = Phase.reduce(Phase.State(), .open)
        #expect(Phase.reduce(opening, .animationFinished(generation: 0)) == opening)
    }

    @Test("Resizing an open hub starts a new animation; resizing while closed or live changes nothing")
    func resize() {
        let open = state(.open, generation: 1)
        let resizing = Phase.reduce(open, .resize)
        #expect(resizing.target == .open)
        #expect(resizing.isAnimating)
        #expect(resizing.generation == 2)
        #expect(!resizing.hasShadow)
        let settled = Phase.reduce(resizing, .animationFinished(generation: 2))
        #expect(settled.hasShadow)
        #expect(Phase.reduce(Phase.State(), .resize) == Phase.State())
        let live = state(.live, generation: 4, live: true)
        #expect(Phase.reduce(live, .resize) == live)
    }

    @Test("A live activity widens the closed notch, and the end of the last one takes it back")
    func liveChanges() {
        let toLive = Phase.reduce(Phase.State(), .liveChanged(true))
        #expect(toLive.target == .live)
        #expect(toLive.isAnimating)
        #expect(toLive.generation == 1)
        #expect(toLive.isLive)
        #expect(toLive.isPanelVisible)
        let live = Phase.reduce(toLive, .animationFinished(generation: 1))
        #expect(live.showsLiveContent)
        let toClosed = Phase.reduce(live, .liveChanged(false))
        #expect(toClosed.target == .closed)
        #expect(toClosed.isAnimating)
        #expect(toClosed.generation == 2)
        #expect(!toClosed.isLive)
        let closed = Phase.reduce(toClosed, .animationFinished(generation: 2))
        #expect(closed.ordersOut)
        // Nothing changes when the answer is the same.
        #expect(Phase.reduce(Phase.State(), .liveChanged(false)) == Phase.State())
        #expect(Phase.reduce(live, .liveChanged(true)) == live)
    }

    @Test("While the hub is open a change of live only records it, and closing then goes to the right place")
    func liveWhileOpen() {
        let open = state(.open, generation: 1)
        let recorded = Phase.reduce(open, .liveChanged(true))
        #expect(recorded.target == .open)
        #expect(recorded.generation == 1)
        #expect(!recorded.isAnimating)
        #expect(recorded.isLive)
        #expect(Phase.reduce(recorded, .close).target == .live)
        let ended = Phase.reduce(recorded, .liveChanged(false))
        #expect(ended.isLive == false)
        #expect(Phase.reduce(ended, .close).target == .closed)
    }

    @Test("When the last live activity ends during a closing towards live, the closing retargets to closed")
    func liveEndsDuringClosing() {
        let closing = Phase.reduce(state(.open, generation: 1, live: true), .close)
        #expect(closing.target == .live)
        let retargeted = Phase.reduce(closing, .liveChanged(false))
        #expect(retargeted.target == .closed)
        #expect(retargeted.isAnimating)
        #expect(retargeted.generation == 3)
        #expect(!retargeted.isLive)
        // The first closing's completion is stale now.
        #expect(Phase.reduce(retargeted, .animationFinished(generation: 2)) == retargeted)
        let closed = Phase.reduce(retargeted, .animationFinished(generation: 3))
        #expect(closed.ordersOut)
    }

    @Test("A live activity that starts during a closing towards closed retargets to live")
    func liveStartsDuringClosing() {
        let closing = Phase.reduce(state(.open, generation: 1), .close)
        #expect(closing.target == .closed)
        let retargeted = Phase.reduce(closing, .liveChanged(true))
        #expect(retargeted.target == .live)
        #expect(retargeted.generation == 3)
        #expect(retargeted.isLive)
        let live = Phase.reduce(retargeted, .animationFinished(generation: 3))
        #expect(live.showsLiveContent)
        #expect(!live.ordersOut)
    }

    @Test("Opening from the live state is an ordinary opening")
    func openFromLive() {
        let live = state(.live, generation: 2, live: true)
        let opening = Phase.reduce(live, .open)
        #expect(opening.target == .open)
        #expect(opening.generation == 3)
        #expect(opening.isLive)
        #expect(!opening.showsLiveContent)
    }

    @Test("The targets are ordered closed, live, open")
    func targetOrder() {
        #expect(Phase.Target.closed < Phase.Target.live)
        #expect(Phase.Target.live < Phase.Target.open)
    }
}
