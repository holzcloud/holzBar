import Testing
@testable import HolzBarCore

@Suite("DDCFailurePolicy")
struct DDCFailurePolicyTests {
    typealias Event = DDCFailurePolicy.Event

    @Test("A survey that asked a display that never answered counts for nothing")
    func surveyWithoutAnswerFromANewDisplay() {
        var policy = DDCFailurePolicy()
        let event = policy.surveyEnded(tried: [1], answered: [])
        #expect(event == .none)
    }

    @Test("A survey that asked a display that answered earlier and got no answer is one failure")
    func surveyWithoutAnswerFromAKnownDisplay() {
        var policy = DDCFailurePolicy()
        _ = policy.surveyEnded(tried: [1], answered: [1])
        let event = policy.surveyEnded(tried: [1], answered: [])
        #expect(event == .failure)
    }

    @Test("A survey that asked only displays that never answered counts for nothing, also next to a known one that was not asked")
    func surveyWithoutAnswerFromOtherDisplays() {
        var policy = DDCFailurePolicy()
        _ = policy.surveyEnded(tried: [2], answered: [2])
        let event = policy.surveyEnded(tried: [1], answered: [])
        #expect(event == .none)
    }

    @Test("A survey that asked a known and a new display and got no answer is one failure")
    func surveyWithoutAnswerFromAKnownAndANewDisplay() {
        var policy = DDCFailurePolicy()
        _ = policy.surveyEnded(tried: [2], answered: [2])
        let event = policy.surveyEnded(tried: [1, 2], answered: [])
        #expect(event == .failure)
    }

    @Test("A survey in which one of two displays answered is a success, and the other never answered")
    func surveyWithOneAnswer() {
        var policy = DDCFailurePolicy()
        let event = policy.surveyEnded(tried: [1, 2], answered: [2])
        #expect(event == .success)
        #expect(policy.hasAnswered(2))
        #expect(!policy.hasAnswered(1))
    }

    @Test("A survey that asked no display counts for nothing")
    func surveyWithoutTries() {
        var policy = DDCFailurePolicy()
        let event = policy.surveyEnded(tried: [], answered: [])
        #expect(event == .none)
    }

    @Test("A single monitor with DDC/CI off never switches the gate off, however often it is asked")
    func aSingleSilentMonitorNeverSwitchesOff() {
        var policy = DDCFailurePolicy()
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        for _ in 0..<10 {
            apply(policy.surveyEnded(tried: [1], answered: []), to: &gate)
        }
        #expect(gate.isAvailable)
    }

    @Test("Three surveys in a row without an answer from a monitor that answered before switch the gate off for the session")
    func threeSurveysSwitchOff() {
        var policy = DDCFailurePolicy()
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        apply(policy.surveyEnded(tried: [1], answered: [1]), to: &gate)
        for _ in 0..<3 {
            apply(policy.surveyEnded(tried: [1], answered: []), to: &gate)
        }
        #expect(gate.state == .unavailable(.failedRepeatedly))
    }

    @Test("A monitor that was silent from the start and starts to answer later is a success, not a failure")
    func aSilentMonitorThatStartsToAnswer() {
        var policy = DDCFailurePolicy()
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        for _ in 0..<2 {
            apply(policy.surveyEnded(tried: [1], answered: []), to: &gate)
        }
        apply(policy.surveyEnded(tried: [1], answered: [1]), to: &gate)
        #expect(gate.isAvailable)
        #expect(policy.hasAnswered(1))
    }

    @Test("A monitor without DDC never switches off a working second monitor")
    func oneMonitorWithoutDDCNeverSwitchesOff() {
        var policy = DDCFailurePolicy()
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        var failures = 0
        for _ in 0..<10 {
            let event = policy.surveyEnded(tried: [1, 2], answered: [2])
            if event == .failure {
                failures += 1
            }
            apply(event, to: &gate)
        }
        #expect(failures == 0)
        #expect(gate.isAvailable)
    }

    @Test("A failed transfer counts only for a display that answered before")
    func transferFailure() {
        var policy = DDCFailurePolicy()
        _ = policy.surveyEnded(tried: [1, 2], answered: [2])
        let known = policy.transferEnded(display: 2, succeeded: false)
        let unknown = policy.transferEnded(display: 1, succeeded: false)
        #expect(known == .failure)
        #expect(unknown == .none)
    }

    @Test("A transfer that worked is a success and marks the display as answered")
    func transferSuccess() {
        var policy = DDCFailurePolicy()
        let event = policy.transferEnded(display: 7, succeeded: true)
        #expect(event == .success)
        #expect(policy.hasAnswered(7))
        let later = policy.transferEnded(display: 7, succeeded: false)
        #expect(later == .failure)
    }

    @Test("Three failed transfers to a working display switch the gate off, a success in between starts again")
    func transfersAndGate() {
        var policy = DDCFailurePolicy()
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        _ = policy.surveyEnded(tried: [2], answered: [2])
        apply(policy.transferEnded(display: 2, succeeded: false), to: &gate)
        apply(policy.transferEnded(display: 2, succeeded: false), to: &gate)
        apply(policy.transferEnded(display: 2, succeeded: true), to: &gate)
        apply(policy.transferEnded(display: 2, succeeded: false), to: &gate)
        apply(policy.transferEnded(display: 2, succeeded: false), to: &gate)
        #expect(gate.isAvailable)
        apply(policy.transferEnded(display: 2, succeeded: false), to: &gate)
        #expect(gate.state == .unavailable(.failedRepeatedly))
    }

    private func apply(_ event: Event, to gate: inout PrivateFeatureGate) {
        switch event {
        case .success: gate.recordSuccess()
        case .failure: gate.recordFailure()
        case .none: break
        }
    }
}
