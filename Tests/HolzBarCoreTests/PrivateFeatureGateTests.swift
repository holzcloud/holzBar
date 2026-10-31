import Testing
@testable import HolzBarCore

@Suite("PrivateFeatureGate")
struct PrivateFeatureGateTests {
    @Test("A gate that is switched on and loaded is available")
    func onAndLoadedIsAvailable() {
        let gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        #expect(gate.state == .available)
        #expect(gate.isAvailable)
    }

    @Test("A gate that is switched off is unavailable and does not ask to load")
    func switchedOffIsUnavailable() {
        let gate = PrivateFeatureGate(isEnabled: false, load: .loaded)
        #expect(gate.state == .unavailable(.switchedOff))
        #expect(!gate.isAvailable)
        #expect(!PrivateFeatureGate.shouldLoad(isEnabled: false))
        #expect(PrivateFeatureGate.shouldLoad(isEnabled: true))
    }

    @Test("A missing framework or symbol makes the gate unavailable with that reason")
    func failedLoadIsUnavailable() {
        #expect(PrivateFeatureGate(isEnabled: true, load: .frameworkMissing).state == .unavailable(.frameworkMissing))
        #expect(PrivateFeatureGate(isEnabled: true, load: .symbolMissing).state == .unavailable(.symbolMissing))
        #expect(!PrivateFeatureGate(isEnabled: true, load: .symbolMissing).isAvailable)
    }

    @Test("The setting off wins over a failed load")
    func switchedOffWinsOverFailedLoad() {
        #expect(PrivateFeatureGate(isEnabled: false, load: .frameworkMissing).state == .unavailable(.switchedOff))
    }

    @Test("Two failures leave the gate available and the third switches it off")
    func thirdFailureSwitchesOff() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        gate.recordFailure()
        gate.recordFailure()
        #expect(gate.isAvailable)
        gate.recordFailure()
        #expect(gate.state == .unavailable(.failedRepeatedly))
        #expect(PrivateFeatureGate.failureLimit == 3)
    }

    @Test("A success resets the count of failures in a row")
    func successResetsTheCount() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        gate.recordFailure()
        gate.recordFailure()
        gate.recordSuccess()
        gate.recordFailure()
        gate.recordFailure()
        #expect(gate.isAvailable)
        gate.recordFailure()
        #expect(gate.state == .unavailable(.failedRepeatedly))
    }

    @Test("Once unavailable, a success or a failure changes nothing")
    func unavailableStays() {
        var failed = PrivateFeatureGate(isEnabled: true, load: .loaded)
        for _ in 0..<3 {
            failed.recordFailure()
        }
        failed.recordSuccess()
        #expect(failed.state == .unavailable(.failedRepeatedly))
        failed.recordFailure()
        #expect(failed.state == .unavailable(.failedRepeatedly))

        var missing = PrivateFeatureGate(isEnabled: true, load: .symbolMissing)
        missing.recordSuccess()
        #expect(missing.state == .unavailable(.symbolMissing))

        var off = PrivateFeatureGate(isEnabled: false, load: .loaded)
        off.recordSuccess()
        #expect(off.state == .unavailable(.switchedOff))
    }

    @Test("Switching the part off and on again starts afresh with an empty count")
    func offAndOnStartsAfresh() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        for _ in 0..<3 {
            gate.recordFailure()
        }
        gate.setEnabled(false, load: .loaded)
        #expect(gate.state == .unavailable(.switchedOff))
        gate.setEnabled(true, load: .loaded)
        #expect(gate.isAvailable)
        gate.recordFailure()
        gate.recordFailure()
        #expect(gate.isAvailable)
    }

    @Test("Switching on with a load that failed gives the reason of the failed load")
    func onAgainWithFailedLoad() {
        var gate = PrivateFeatureGate(isEnabled: false, load: .loaded)
        gate.setEnabled(true, load: .frameworkMissing)
        #expect(gate.state == .unavailable(.frameworkMissing))
    }

    @Test("Setting the switch to the value it already has changes nothing")
    func sameSwitchChangesNothing() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        gate.recordFailure()
        gate.recordFailure()
        gate.setEnabled(true, load: .loaded)
        gate.recordFailure()
        #expect(gate.state == .unavailable(.failedRepeatedly))
    }
}
