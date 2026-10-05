import Testing
@testable import HolzBarCore

@Suite("PresentationSignals")
struct PresentationSignalsTests {
    @Test("Mirroring presents")
    func mirroringPresents() {
        #expect(PresentationSignals.isPresenting(mirroredDisplays: 1, runningBundleIDs: []))
        #expect(PresentationSignals.isPresenting(mirroredDisplays: 2, runningBundleIDs: ["com.apple.finder"]))
    }

    @Test("Screen sharing presents")
    func screenSharingPresents() {
        #expect(PresentationSignals.isPresenting(mirroredDisplays: 0, runningBundleIDs: ["com.apple.screensharing.agent"]))
        // Viewing another Mac does not show this one.
        #expect(!PresentationSignals.isPresenting(mirroredDisplays: 0, runningBundleIDs: ["com.apple.ScreenSharing"]))
        #expect(!PresentationSignals.isPresenting(mirroredDisplays: 0, runningBundleIDs: []))
    }

    @Test("The first set is evaluated")
    func firstSetIsEvaluated() {
        var trigger = PresentationSignals.Trigger()
        let evaluates = trigger.needsEvaluation(running: ["a"])
        #expect(evaluates)
        #expect(trigger.evaluated == ["a"])
    }

    @Test("The same set is not evaluated again")
    func sameSetIsNotEvaluated() {
        var trigger = PresentationSignals.Trigger()
        _ = trigger.needsEvaluation(running: ["a", "b"])
        // A second instance of a running app, or a helper that restarted.
        let again = trigger.needsEvaluation(running: ["a", "b"])
        #expect(!again)
        // The order the identifiers were inserted in does not matter.
        let reordered = trigger.needsEvaluation(running: Set(["b", "a"]))
        #expect(!reordered)
    }

    @Test("Screen sharing starting and ending is evaluated")
    func screenSharingIsEvaluated() {
        var trigger = PresentationSignals.Trigger()
        _ = trigger.needsEvaluation(running: ["com.apple.finder"])
        let started = trigger.needsEvaluation(running: ["com.apple.finder", "com.apple.screensharing.agent"])
        #expect(started)
        let ended = trigger.needsEvaluation(running: ["com.apple.finder"])
        #expect(ended)
    }

    @Test("A reset evaluates the next set")
    func resetEvaluatesTheNextSet() {
        var trigger = PresentationSignals.Trigger()
        _ = trigger.needsEvaluation(running: ["a"])
        trigger.reset()
        #expect(trigger.evaluated == nil)
        let evaluates = trigger.needsEvaluation(running: ["a"])
        #expect(evaluates)
    }
}
