import Foundation
import Testing
@testable import HolzBarCore

@Suite("HubStatusPills")
struct HubStatusPillsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func activity(
        _ id: String,
        module: String = "live-activities",
        priority: Int = 10,
        started: TimeInterval = 0,
        finished: TimeInterval? = nil
    ) -> LiveActivity {
        LiveActivity(
            id: id,
            moduleID: module,
            kind: .other,
            symbol: "star",
            title: id,
            priority: priority,
            startedAt: now.addingTimeInterval(started),
            finishedAt: finished.map { now.addingTimeInterval($0) }
        )
    }

    private func place(_ pills: [String], _ activities: [LiveActivity]) -> HubStatusPills.Placement {
        HubStatusPills.place(pillModuleIDs: pills, activities: activities, now: now)
    }

    @Test("The Timers pill is left, the top other activity is right, the timer is not counted")
    func timersLeftOthersRight() {
        let placement = place(
            ["timers", "now-playing"],
            [
                activity("timer", module: "timers", priority: 15),
                activity("camera", priority: 20),
                activity("download", priority: 10),
            ]
        )
        #expect(placement.left == "timers")
        #expect(placement.right?.id == "camera")
        #expect(placement.hiddenCount == 1)
    }

    @Test("Without the Timers pill nothing is left, and a timer's activity never becomes the right pill")
    func noTimersPill() {
        let placement = place(["now-playing"], [activity("timer", module: "timers", priority: 15)])
        #expect(placement.left == nil)
        #expect(placement.right == nil)
        #expect(placement.hiddenCount == 0)
        let withOther = place(["now-playing"], [
            activity("timer", module: "timers", priority: 99),
            activity("download", priority: 10),
        ])
        #expect(withOther.right?.id == "download")
        #expect(withOther.hiddenCount == 0)
    }

    @Test("Only timer activities, or nothing at all, leave the right side empty")
    func empty() {
        let onlyTimers = place(["timers"], [activity("a", module: "timers"), activity("b", module: "timers")])
        #expect(onlyTimers.left == "timers")
        #expect(onlyTimers.right == nil)
        #expect(onlyTimers.hiddenCount == 0)
        let nothing = place([], [])
        #expect(nothing.left == nil)
        #expect(nothing.right == nil)
        #expect(nothing.hiddenCount == 0)
    }

    @Test("A low battery beats the camera, and the newer start wins at the same priority")
    func fixedPriority() {
        let battery = place(
            ["timers"],
            [activity("camera", priority: 20), activity("battery", module: "accessory-alerts", priority: 30)]
        )
        #expect(battery.right?.id == "battery")
        #expect(battery.hiddenCount == 1)
        let newer = place(
            [],
            [activity("older", priority: 10, started: -60), activity("newer", priority: 10, started: -5)]
        )
        #expect(newer.right?.id == "newer")
    }

    @Test("A finished activity that has stayed its time is neither shown nor counted")
    func expired() {
        let hold = HubActivityBoard.finishedHold
        let placement = place(
            [],
            [
                activity("gone", priority: 30, started: -100, finished: -hold),
                activity("kept", priority: 10, started: -50),
            ]
        )
        #expect(placement.right?.id == "kept")
        #expect(placement.hiddenCount == 0)
        let still = place([], [activity("done", priority: 10, started: -50, finished: -(hold - 1))])
        #expect(still.right?.id == "done")
    }

    @Test("Seven running activities of other modules give one right pill and six counted")
    func manyActivities() {
        let activities = (0..<7).map { activity("a\($0)", started: Double(-$0)) }
        let placement = place(["timers"], activities)
        #expect(placement.right != nil)
        #expect(placement.hiddenCount == 6)
        #expect(placement.rightBoard.listed.count == HubActivityBoard.maximumListed)
    }

    @Test("The left pill belongs to a module of the notch area in the catalogue")
    func leftModule() {
        #expect(ModuleCatalog.all.contains { $0.id == HubStatusPills.leftModuleID })
        #expect(HubStatusPills.leftModuleID == "timers")
    }
}
