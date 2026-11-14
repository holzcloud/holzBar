import Foundation
import Testing
@testable import HolzBarCore

@Suite("HubContext")
struct HubContextTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let tabs = ["timers", "calendar", "live-activities", "now-playing"]

    private func meeting(from start: TimeInterval, for length: TimeInterval = 1800) -> HubContext.Meeting {
        HubContext.Meeting(start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + length))
    }

    private func inputs(
        tabs: [String]? = nil,
        signals: [HubContext.ModuleSignal] = [],
        liveOwner: String? = nil,
        lastChosen: String? = nil,
        showsActiveFirst: Bool = true
    ) -> HubContext.Inputs {
        HubContext.Inputs(
            now: now,
            moduleTabs: tabs ?? self.tabs,
            signals: signals,
            liveOwner: liveOwner,
            lastChosen: lastChosen,
            showsActiveFirst: showsActiveFirst
        )
    }

    private func meetings(_ list: [HubContext.Meeting], of module: String = "calendar") -> HubContext.ModuleSignal {
        HubContext.ModuleSignal(moduleID: module, signal: .meetings(list))
    }

    private func playing(_ isPlaying: Bool) -> HubContext.ModuleSignal {
        HubContext.ModuleSignal(moduleID: "now-playing", signal: .playing(isPlaying))
    }

    @Test("A meeting that starts within 15 minutes comes first, 15 minutes included, 16 not")
    func meetingSoon() {
        let tenMinutes = HubContext.decide(inputs(signals: [meetings([meeting(from: 600)])]))
        #expect(tenMinutes == HubContext.Decision(moduleID: "calendar", reason: .meetingSoon))
        let fifteen = HubContext.decide(inputs(signals: [meetings([meeting(from: 900)])]))
        #expect(fifteen == HubContext.Decision(moduleID: "calendar", reason: .meetingSoon))
        let sixteen = HubContext.decide(inputs(signals: [meetings([meeting(from: 960)])]))
        #expect(sixteen == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
    }

    @Test("A running meeting is meetingNow and beats a soon one; an ended or malformed meeting never counts")
    func meetingNow() {
        let running = HubContext.decide(inputs(signals: [meetings([meeting(from: 300), meeting(from: -600)])]))
        #expect(running == HubContext.Decision(moduleID: "calendar", reason: .meetingNow))
        let ended = meeting(from: -3600, for: 1800)
        let endsNow = meeting(from: -1800, for: 1800)
        let backwards = HubContext.Meeting(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(-120))
        let empty = HubContext.Meeting(start: now, end: now)
        let none = HubContext.decide(inputs(signals: [meetings([ended, endsNow, backwards, empty])]))
        #expect(none == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
    }

    @Test("A meeting signal of a module that is not a tab is ignored")
    func meetingOfMissingTab() {
        let decision = HubContext.decide(
            inputs(tabs: ["timers", "now-playing"], signals: [meetings([meeting(from: 60)])])
        )
        #expect(decision == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
    }

    @Test("A live owner with a tab is in front; an owner without a tab falls back to Live activities, else to music")
    func liveActivity() {
        let owned = HubContext.decide(inputs(liveOwner: "timers"))
        #expect(owned == HubContext.Decision(moduleID: "timers", reason: .liveActivity))
        let foreign = HubContext.decide(inputs(liveOwner: "accessory-alerts"))
        #expect(foreign == HubContext.Decision(moduleID: "live-activities", reason: .liveActivity))
        let noList = HubContext.decide(
            inputs(tabs: ["timers", "now-playing"], signals: [playing(true)], liveOwner: "accessory-alerts")
        )
        #expect(noList == HubContext.Decision(moduleID: "now-playing", reason: .music))
        let nothing = HubContext.decide(inputs(tabs: ["timers"], liveOwner: "accessory-alerts"))
        #expect(nothing == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
    }

    @Test("A meeting beats a live activity, a live activity beats music, music beats the Overview")
    func order() {
        let all = HubContext.decide(
            inputs(signals: [playing(true), meetings([meeting(from: 120)])], liveOwner: "timers")
        )
        #expect(all == HubContext.Decision(moduleID: "calendar", reason: .meetingSoon))
        let liveAndMusic = HubContext.decide(inputs(signals: [playing(true)], liveOwner: "timers"))
        #expect(liveAndMusic == HubContext.Decision(moduleID: "timers", reason: .liveActivity))
        let music = HubContext.decide(inputs(signals: [playing(true)]))
        #expect(music == HubContext.Decision(moduleID: "now-playing", reason: .music))
        let paused = HubContext.decide(inputs(signals: [playing(false)]))
        #expect(paused == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
        let nothing = HubContext.decide(inputs())
        #expect(nothing == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
    }

    @Test("With the setting off the module last chosen is in front, even while a meeting runs")
    func settingOff() {
        let chosen = HubContext.decide(
            inputs(signals: [meetings([meeting(from: -60)])], lastChosen: "timers", showsActiveFirst: false)
        )
        #expect(chosen == HubContext.Decision(moduleID: "timers", reason: .chosen))
        let gone = HubContext.decide(
            inputs(signals: [meetings([meeting(from: -60)])], lastChosen: "display-controls", showsActiveFirst: false)
        )
        #expect(gone == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .chosen))
        let none = HubContext.decide(inputs(lastChosen: nil, showsActiveFirst: false))
        #expect(none == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .chosen))
    }

    @Test("A session fronts the opening decision; a pick fronts the module and is the only thing to remember")
    func picks() {
        let opening = HubContext.Decision(moduleID: "timers", reason: .liveActivity)
        var session = HubContext.Session(opening: opening)
        #expect(session.front == opening)
        #expect(!session.hasPick)
        let remembered = session.pick("calendar", moduleTabs: tabs)
        #expect(remembered == "calendar")
        #expect(session.front == HubContext.Decision(moduleID: "calendar", reason: .chosen))
        #expect(session.hasPick)
        // A module that is not a tab becomes the Overview.
        let overview = session.pick("missing", moduleTabs: tabs)
        #expect(overview == HubTabStrip.overviewID)
        #expect(session.front == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .chosen))
    }

    @Test("A temporary pick fronts the module, counts as a pick and remembers nothing")
    func temporaryPick() {
        var session = HubContext.Session(opening: HubContext.Decision(moduleID: "timers", reason: .liveActivity))
        session.pickTemporarily("file-drop", moduleTabs: tabs + ["file-drop"])
        #expect(session.front == HubContext.Decision(moduleID: "file-drop", reason: .chosen))
        #expect(session.hasPick)
        // The reasons of a context decision never ask to be remembered, a pick does.
        var other = HubContext.Session(opening: HubContext.Decision(moduleID: "calendar", reason: .meetingNow))
        #expect(other.front.reason != .chosen)
        other.pickTemporarily("missing", moduleTabs: tabs)
        #expect(other.front == HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .chosen))
    }

    @Test("Only a user's pick yields a module to remember; the opening, a late decision and a temporary pick never do")
    func onlyAPickIsRemembered() {
        // The opening decision and the late decision return no module at all; only pick does.
        var late = HubContext.Session(opening: HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
        let accepted = late.reconsider(HubContext.Decision(moduleID: "calendar", reason: .meetingSoon), elapsed: 0.4)
        #expect(accepted)
        #expect(!late.hasPick)
        #expect(late.front.reason == .meetingSoon)
        // After a late decision a pick still remembers its own module.
        let result1 = late.pick("timers", moduleTabs: tabs)
        #expect(result1 == "timers")
        // A temporary pick sets hasPick, so no late decision follows it.
        var dragged = HubContext.Session(opening: HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview))
        dragged.pickTemporarily("timers", moduleTabs: tabs)
        let refused = dragged.reconsider(HubContext.Decision(moduleID: "calendar", reason: .meetingNow), elapsed: 0.1)
        #expect(!refused)
        #expect(dragged.front == HubContext.Decision(moduleID: "timers", reason: .chosen))
    }

    @Test("A late decision succeeds once, only without a pick, within one second and only for a meeting of another module")
    func lateDecision() {
        let overview = HubContext.Decision(moduleID: HubTabStrip.overviewID, reason: .overview)
        let meetingSoon = HubContext.Decision(moduleID: "calendar", reason: .meetingSoon)
        let meetingNow = HubContext.Decision(moduleID: "calendar", reason: .meetingNow)

        var once = HubContext.Session(opening: overview)
        let result2 = once.reconsider(meetingSoon, elapsed: 1)
        #expect(result2)
        #expect(once.hasReconsidered)
        #expect(once.front == meetingSoon)
        let result3 = once.reconsider(meetingNow, elapsed: 0.5)
        #expect(!result3)
        #expect(once.front == meetingSoon)

        var picked = HubContext.Session(opening: overview)
        _ = picked.pick("timers", moduleTabs: tabs)
        let result4 = picked.reconsider(meetingSoon, elapsed: 0.2)
        #expect(!result4)
        #expect(picked.front == HubContext.Decision(moduleID: "timers", reason: .chosen))

        var late = HubContext.Session(opening: overview)
        let result5 = late.reconsider(meetingSoon, elapsed: 1.5)
        #expect(!result5)
        #expect(late.front == overview)
        #expect(!late.hasReconsidered)

        var live = HubContext.Session(opening: overview)
        let result6 = live.reconsider(HubContext.Decision(moduleID: "timers", reason: .liveActivity), elapsed: 0.2)
        #expect(!result6)
        let result7 = live.reconsider(HubContext.Decision(moduleID: "now-playing", reason: .music), elapsed: 0.2)
        #expect(!result7)
        #expect(live.front == overview)

        var same = HubContext.Session(opening: meetingSoon)
        let result8 = same.reconsider(meetingNow, elapsed: 0.2)
        #expect(!result8)
        #expect(same.front == meetingSoon)

        var notANumber = HubContext.Session(opening: overview)
        let result9 = notANumber.reconsider(meetingSoon, elapsed: .nan)
        #expect(!result9)
    }

    @Test("The constants: the Live activities module is in the catalog, the lead is 900 seconds, the window one second")
    func constants() {
        #expect(ModuleCatalog.all.contains { $0.id == HubContext.liveActivitiesModuleID })
        #expect(HubContext.meetingLead == 900)
        #expect(HubContext.lateDecisionWindow == 1)
        #expect(HubContext.Reason.allCases.count == 6)
    }
}
