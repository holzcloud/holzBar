import Foundation
import Testing
@testable import HolzBarCore

@Suite("FocusChangeRehide")
struct FocusChangeRehideTests {
    private static let ownPID: pid_t = 100
    private static let appA: pid_t = 200
    private static let appB: pid_t = 300

    /// Feeds the frontmost applications to the filter and returns which were focus changes.
    private static func focusChanges(_ filter: inout FocusChangeRehide, for pids: [pid_t]) -> [Bool] {
        pids.map { filter.isFocusChange(to: $0, ownPID: ownPID) }
    }

    @Test("A to holzBar to A is no focus change")
    func returnToTheSameAppIsNoFocusChange() {
        var filter = FocusChangeRehide(frontmostPID: Self.appA, ownPID: Self.ownPID)
        let changes = Self.focusChanges(&filter, for: [Self.ownPID, Self.appA])
        #expect(changes == [false, false])
        #expect(filter.lastPID == Self.appA)
    }

    @Test("A to holzBar to B is a focus change")
    func switchThroughHolzBarIsAFocusChange() {
        var filter = FocusChangeRehide(frontmostPID: Self.appA, ownPID: Self.ownPID)
        let changes = Self.focusChanges(&filter, for: [Self.ownPID, Self.appB])
        #expect(changes == [false, true])
        #expect(filter.lastPID == Self.appB)
    }

    @Test("A to B is a focus change")
    func switchBetweenAppsIsAFocusChange() {
        var filter = FocusChangeRehide(frontmostPID: Self.appA, ownPID: Self.ownPID)
        let changes = Self.focusChanges(&filter, for: [Self.appB, Self.appA])
        #expect(changes == [true, true])
    }

    @Test("The first app after a launch without one counts as a focus change")
    func firstEventWithoutLastAppIsAFocusChange() {
        var filter = FocusChangeRehide(frontmostPID: nil, ownPID: Self.ownPID)
        #expect(filter == FocusChangeRehide())
        #expect(filter.lastPID == nil)
        let changes = Self.focusChanges(&filter, for: [Self.appA])
        #expect(changes == [true])
        #expect(filter.lastPID == Self.appA)
    }

    @Test("holzBar in front at launch is not recorded")
    func holzBarAtLaunchIsNotRecorded() {
        var filter = FocusChangeRehide(frontmostPID: Self.ownPID, ownPID: Self.ownPID)
        #expect(filter.lastPID == nil)
        let changes = Self.focusChanges(&filter, for: [Self.ownPID, Self.appA])
        #expect(changes == [false, true])
    }

    @Test("The strategy applies only with Automatically rehide on")
    func appliesOnlyWithAutoRehide() {
        #expect(FocusChangeRehide.applies(autoRehide: true, rehidesOnFocusChange: true))
        #expect(!FocusChangeRehide.applies(autoRehide: false, rehidesOnFocusChange: true))
        #expect(!FocusChangeRehide.applies(autoRehide: true, rehidesOnFocusChange: false))
        #expect(!FocusChangeRehide.applies(autoRehide: false, rehidesOnFocusChange: false))
    }
}
