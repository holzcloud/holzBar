import Testing
@testable import HolzBarCore

@Suite("WhatsNewPolicy")
struct WhatsNewPolicyTests {
    private let known = ["1.0.1", "1.0.0"]

    private func decide(
        lastSeen: String?,
        current: String?,
        isFreshInstall: Bool = false,
        showsAfterUpdate: Bool = true,
        known: [String]? = nil
    ) -> WhatsNewPolicy.Decision {
        WhatsNewPolicy.decide(
            lastSeen: lastSeen,
            current: current,
            isFreshInstall: isFreshInstall,
            showsAfterUpdate: showsAfterUpdate,
            knownVersions: known ?? self.known
        )
    }

    private let nothing = WhatsNewPolicy.Decision(show: false, record: nil)

    @Test("A build without a history entry shows nothing and records nothing")
    func devBuildShowsNothing() {
        #expect(decide(lastSeen: "1.0.0", current: "0.0.5") == nothing)
        #expect(decide(lastSeen: nil, current: nil) == nothing)
        #expect(decide(lastSeen: nil, current: "garbage") == nothing)
        #expect(decide(lastSeen: nil, current: "0.0.5", isFreshInstall: true) == nothing)
        #expect(decide(lastSeen: "1.0.0", current: "1.0.1", known: []) == nothing)
    }

    @Test("A fresh install shows nothing and records the version")
    func freshInstallRecordsOnly() {
        let recorded = WhatsNewPolicy.Decision(show: false, record: "1.0.1")
        #expect(decide(lastSeen: nil, current: "1.0.1", isFreshInstall: true) == recorded)
        #expect(decide(lastSeen: nil, current: "1.0.1-beta1", isFreshInstall: true) == recorded)
    }

    @Test("An install without a stored version counts as having seen 1.0.0")
    func missingValueCountsAsBaseline() {
        #expect(decide(lastSeen: nil, current: "1.0.1-beta1") == WhatsNewPolicy.Decision(show: true, record: "1.0.1"))
        #expect(decide(lastSeen: nil, current: "1.0.0") == nothing)
    }

    @Test("A beta shows the window once, the stable of the same version does not")
    func betaThenStable() {
        #expect(decide(lastSeen: "1.0.1", current: "1.0.1-beta2") == nothing)
        #expect(decide(lastSeen: "1.0.1", current: "1.0.1") == nothing)
        #expect(decide(lastSeen: "1.0.0", current: "1.0.1") == WhatsNewPolicy.Decision(show: true, record: "1.0.1"))
        #expect(decide(lastSeen: "1.0.0", current: "1.0.1-beta1") == WhatsNewPolicy.Decision(show: true, record: "1.0.1"))
    }

    @Test("A downgrade shows nothing and never lowers the stored value")
    func downgradeShowsNothing() {
        #expect(decide(lastSeen: "1.0.2", current: "1.0.1") == nothing)
    }

    @Test("A garbage stored value behaves like a missing one")
    func garbageStoredValue() {
        #expect(decide(lastSeen: "garbage", current: "1.0.1") == WhatsNewPolicy.Decision(show: true, record: "1.0.1"))
        #expect(decide(lastSeen: "", current: "1.0.1") == WhatsNewPolicy.Decision(show: true, record: "1.0.1"))
        #expect(decide(lastSeen: "99999999999999999999.0", current: "1.0.1") == WhatsNewPolicy.Decision(show: true, record: "1.0.1"))
        #expect(decide(lastSeen: "garbage", current: "1.0.0") == nothing)
    }

    @Test("With the switch off nothing shows, but the version is still recorded")
    func switchOffStillRecords() {
        #expect(
            decide(lastSeen: "1.0.0", current: "1.0.1", showsAfterUpdate: false)
                == WhatsNewPolicy.Decision(show: false, record: "1.0.1")
        )
    }

    @Test("A show always comes with a record")
    func showComesWithRecord() {
        for lastSeen in [nil, "1.0.0", "garbage"] {
            let decision = decide(lastSeen: lastSeen, current: "1.0.1")
            #expect(!decision.show || decision.record != nil)
        }
    }

    @Test("The tabs list the known versions up to the running one")
    func tabsUpToTheRunningVersion() {
        let all = ["1.0.2", "1.0.1", "1.0.0"]
        #expect(WhatsNewPolicy.tabs(knownVersions: all, current: "1.0.1-beta1") == .init(versions: ["1.0.1", "1.0.0"], installed: "1.0.1"))
        #expect(WhatsNewPolicy.tabs(knownVersions: all, current: "1.0.1") == .init(versions: ["1.0.1", "1.0.0"], installed: "1.0.1"))
        #expect(WhatsNewPolicy.tabs(knownVersions: all, current: "1.0.0") == .init(versions: ["1.0.0"], installed: "1.0.0"))
        #expect(WhatsNewPolicy.tabs(knownVersions: all, current: "1.0.2") == .init(versions: all, installed: "1.0.2"))
    }

    @Test("An unknown running version shows every version without a dot")
    func tabsForAnUnknownVersion() {
        let all = ["1.0.2", "1.0.1", "1.0.0"]
        let expected = WhatsNewPolicy.Tabs(versions: all, installed: nil)
        #expect(WhatsNewPolicy.tabs(knownVersions: all, current: "0.0.5") == expected)
        #expect(WhatsNewPolicy.tabs(knownVersions: all, current: nil) == expected)
        #expect(WhatsNewPolicy.tabs(knownVersions: all, current: "garbage") == expected)
    }

    @Test("A running version without an entry has no dot")
    func tabsWithoutAnEntry() {
        #expect(
            WhatsNewPolicy.tabs(knownVersions: ["1.0.1", "1.0.0"], current: "1.0.2")
                == .init(versions: ["1.0.1", "1.0.0"], installed: nil)
        )
        #expect(WhatsNewPolicy.tabs(knownVersions: [], current: "1.0.1") == .init(versions: [], installed: nil))
    }
}
