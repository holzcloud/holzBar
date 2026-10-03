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
}
