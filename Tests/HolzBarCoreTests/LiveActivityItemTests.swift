import Foundation
import Testing
@testable import HolzBarCore

@Suite("Live Activity items")
struct LiveActivityItemTests {
    private let known: Set<String> = [
        "com.apple.menuextra.battery",
        "com.apple.menuextra.clock",
        "com.apple.menuextra.wifi",
        "com.apple.menuextra.controlcenter"
    ]
    private let agent = LiveActivityItem.menuBarAgentBundleID

    private func isLive(_ owner: String, _ identifier: String) -> Bool {
        LiveActivityItem.isLiveActivity(ownerBundleID: owner, identifier: identifier, knownSystemIdentifiers: known)
    }

    @Test("MenuBarAgent's bundle identifier")
    func agentIdentifier() {
        #expect(LiveActivityItem.menuBarAgentBundleID == "com.apple.MenuBarAgent")
    }

    @Test("A known system item of MenuBarAgent stays managed as today")
    func knownSystemItemsStayManaged() {
        for identifier in known {
            #expect(!isLive(agent, identifier))
        }
    }

    @Test("An unknown item MenuBarAgent draws is excluded, fail safe")
    func unknownAgentItemIsExcluded() {
        #expect(isLive(agent, "Item-5"))
        #expect(isLive(agent, ""))
        #expect(isLive(agent, "com.apple.menuextra.something-new"))
        // The app-control indicator of 27.3 is never offered for hiding, whatever it is called.
        #expect(isLive(agent, "com.apple.menuextra.appcontrol"))
    }

    @Test("An identifier that names a Live Activity is excluded for any owner, in any case")
    func markersAreMatched() {
        #expect(isLive("com.apple.controlcenter", "com.apple.LiveActivity.timer"))
        #expect(isLive("com.example.host", "SBActivityKitHost.1"))
        #expect(isLive("com.example.host", "my.liveactivity.item"))
        #expect(isLive("com.example.host", "ACTIVITYKIT-recording"))
    }

    @Test("Everything else behaves as in 1.1.1")
    func otherItemsAreManaged() {
        #expect(!isLive("com.apple.controlcenter", "com.apple.menuextra.focusmode"))
        #expect(!isLive("com.example.app", "Item-0"))
        #expect(!isLive("com.example.app", ""))
        // A known identifier of another owner is not special either way.
        #expect(!isLive("com.example.app", "com.apple.menuextra.clock"))
    }

    @Test("A pure host is never concealed")
    func pureHostIsUnconcealable() {
        let owners = LiveActivityItem.unconcealableOwners(
            items: [
                (ownerBundleID: "com.example.host", identifier: "LiveActivity.a"),
                (ownerBundleID: "com.example.host", identifier: "ActivityKit.b")
            ],
            knownSystemIdentifiers: known
        )
        #expect(owners == ["com.example.host"])
    }

    @Test("An owner with a plain item as well can be concealed")
    func mixedOwnerIsConcealable() {
        let owners = LiveActivityItem.unconcealableOwners(
            items: [
                (ownerBundleID: "com.example.mixed", identifier: "LiveActivity.a"),
                (ownerBundleID: "com.example.mixed", identifier: "Item-1")
            ],
            knownSystemIdentifiers: known
        )
        #expect(owners.isEmpty)
    }

    @Test("MenuBarAgent is never listed, and an empty read lists nobody")
    func agentAndEmpty() {
        let owners = LiveActivityItem.unconcealableOwners(
            items: [
                (ownerBundleID: agent, identifier: "Item-5"),
                (ownerBundleID: agent, identifier: "")
            ],
            knownSystemIdentifiers: known
        )
        #expect(owners.isEmpty)
        #expect(LiveActivityItem.unconcealableOwners(items: [], knownSystemIdentifiers: known).isEmpty)
    }

    @Test("The measured tables are empty until probe P4 fills them")
    func measuredTablesAreEmpty() {
        // Probe P4 on a macOS 27.3 Mac fills both tables, one fixture here per measured case.
        #expect(LiveActivityItem.measuredIdentifiers.isEmpty)
        #expect(LiveActivityItem.measuredHosts.isEmpty)
    }

    @Test("The markers are lower case, so the match can lower-case the identifier once")
    func markersAreLowerCase() {
        #expect(LiveActivityItem.identifierMarkers.allSatisfy { $0 == $0.lowercased() })
    }
}
