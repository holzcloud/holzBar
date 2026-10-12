import Foundation
import Testing
@testable import HolzBarCore

@Suite("WidgetScriptSharing")
struct WidgetScriptSharingTests {
    private let first = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000001")!
    private let second = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000002")!
    private let third = UUID(uuidString: "0A1B2C3D-0000-4000-8000-000000000003")!

    @Test("A widget turned away by a busy script takes over the result of the run that ended (WR-03)")
    func waitingWidgetTakesOver() {
        let takers = WidgetScriptSharing.takingOver(
            script: "battery.sh",
            finished: first,
            waiting: [second: "battery.sh"]
        )
        #expect(takers == [second])
    }

    @Test("Only widgets bound to the script that ran take its result, and never the widget that ran it")
    func onlyTheSameScript() {
        let takers = WidgetScriptSharing.takingOver(
            script: "battery.sh",
            finished: first,
            waiting: [first: "battery.sh", second: "cpu.sh", third: "battery.sh"]
        )
        #expect(takers == [third])
    }

    @Test("Nothing waits, nothing is given")
    func nobodyWaits() {
        #expect(WidgetScriptSharing.takingOver(script: "battery.sh", finished: first, waiting: [:]).isEmpty)
    }

    @Test("The order is stable")
    func stableOrder() {
        let takers = WidgetScriptSharing.takingOver(
            script: "a.sh",
            finished: first,
            waiting: [third: "a.sh", second: "a.sh"]
        )
        #expect(takers == [second, third])
    }
}
