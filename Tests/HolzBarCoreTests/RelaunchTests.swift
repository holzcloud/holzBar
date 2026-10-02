import Foundation
import Testing
@testable import HolzBarCore

@Suite("Relaunch")
struct RelaunchTests {
    @Test("The previous instance is handed over in the environment")
    func previousInstanceIsHandedOver() {
        #expect(Relaunch.previousPID(in: Relaunch.environment(previousPID: 4242)) == 4242)
    }

    @Test("A launch without a hand-off has no previous instance")
    func launchWithoutHandOff() {
        #expect(Relaunch.previousPID(in: [:]) == nil)
        #expect(Relaunch.previousPID(in: ["PATH": "/usr/bin"]) == nil)
    }

    @Test("A malformed hand-off is ignored")
    func malformedHandOffIsIgnored() {
        for value in ["abc", "0", "-5", "99999999999", ""] {
            #expect(Relaunch.previousPID(in: [Relaunch.previousInstanceKey: value]) == nil)
        }
    }
}
