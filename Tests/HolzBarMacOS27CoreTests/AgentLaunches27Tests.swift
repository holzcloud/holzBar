import Foundation
import Testing
@testable import HolzBarMacOS27Core

@Suite("AgentLaunches27")
struct AgentLaunches27Tests {
    typealias Instance = AgentLaunches27.Instance

    let rectangle: Instance = ("com.knollsoft.Rectangle", "/Applications/Rectangle.app", .accessory)
    let webKitGPU: Instance = (
        "com.apple.WebKit.GPU",
        "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc",
        .accessory
    )
    let slackHelper: Instance = ("com.tinyspeck.slackmacgap.helper", "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app", .accessory)
    let finder: Instance = ("com.apple.finder", "/System/Library/CoreServices/Finder.app", .regular)

    @Test("Top-level applications are standalone, whatever their policy")
    func topLevelApplicationsAreStandalone() {
        #expect(AgentLaunches27.isStandalone(bundlePath: "/Applications/Rectangle.app", policy: .accessory))
        #expect(AgentLaunches27.isStandalone(bundlePath: "/System/Library/CoreServices/SSMenuAgent.app", policy: .accessory))
        #expect(AgentLaunches27.isStandalone(bundlePath: "/Applications/OneDrive.app", policy: .prohibited))
        #expect(AgentLaunches27.isStandalone(bundlePath: "/Applications/Rectangle.APP", policy: .accessory))
    }

    @Test("Helpers and other bundles are not standalone")
    func helpersAreNotStandalone() {
        #expect(!AgentLaunches27.isStandalone(bundlePath: webKitGPU.bundlePath, policy: .accessory))
        let braveRenderer = "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/"
            + "Versions/1.0/Helpers/Brave Browser Helper (Renderer).app"
        #expect(!AgentLaunches27.isStandalone(bundlePath: braveRenderer, policy: .accessory))
        #expect(!AgentLaunches27.isStandalone(bundlePath: slackHelper.bundlePath, policy: .accessory))
        #expect(!AgentLaunches27.isStandalone(bundlePath: "/System/Library/CoreServices/RemoteManagement/ScreensharingAgent.bundle", policy: .accessory))
        #expect(!AgentLaunches27.isStandalone(bundlePath: nil, policy: .accessory))
    }

    @Test("A nested regular app is standalone")
    func nestedRegularAppIsStandalone() {
        #expect(AgentLaunches27.isStandalone(bundlePath: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app", policy: .regular))
    }

    @Test("An unchanged set does nothing")
    func unchangedSetDoesNothing() {
        let previous: Set = [finder.bundleID, webKitGPU.bundleID]
        // A second WebKit process starts: the set of identifiers stays as it was.
        let reaction = AgentLaunches27.reaction(previous: previous, instances: [finder, webKitGPU, webKitGPU], known: [], concealedInLayout: [])
        #expect(reaction.graces.isEmpty)
        #expect(!reaction.updatesConcealment)
        #expect(reaction.running == previous)
    }

    @Test("A helper that launches does nothing")
    func helperLaunchDoesNothing() {
        let reaction = AgentLaunches27.reaction(previous: [finder.bundleID], instances: [finder, webKitGPU], known: [], concealedInLayout: [])
        #expect(!reaction.updatesConcealment)
        #expect(reaction.graces.isEmpty)
    }

    @Test("An unknown standalone app that launches updates")
    func unknownStandaloneLaunchUpdates() {
        let reaction = AgentLaunches27.reaction(previous: [finder.bundleID], instances: [finder, rectangle], known: [], concealedInLayout: [])
        #expect(reaction.updatesConcealment)
        #expect(reaction.graces.isEmpty)
    }

    @Test("A known visible app that launches updates without a grace")
    func knownVisibleLaunchUpdates() {
        let reaction = AgentLaunches27.reaction(
            previous: [finder.bundleID],
            instances: [finder, rectangle],
            known: [rectangle.bundleID],
            concealedInLayout: []
        )
        #expect(reaction.updatesConcealment)
        #expect(reaction.graces.isEmpty)
    }

    @Test("A known app in a concealed section gets a grace")
    func knownConcealedLaunchGetsGrace() {
        let reaction = AgentLaunches27.reaction(
            previous: [finder.bundleID],
            instances: [finder, rectangle],
            known: [rectangle.bundleID],
            concealedInLayout: [rectangle.bundleID]
        )
        #expect(reaction.updatesConcealment)
        #expect(reaction.graces == [rectangle.bundleID])
    }

    @Test("A known app counts even when it is nested")
    func knownNestedAppCounts() {
        let reaction = AgentLaunches27.reaction(
            previous: [finder.bundleID],
            instances: [finder, slackHelper],
            known: [slackHelper.bundleID],
            concealedInLayout: []
        )
        #expect(reaction.updatesConcealment)
    }

    @Test("Only known apps that quit update")
    func onlyKnownQuitsUpdate() {
        let all: Set = [finder.bundleID, rectangle.bundleID, webKitGPU.bundleID]
        let knownQuit = AgentLaunches27.reaction(previous: all, instances: [finder, webKitGPU], known: [rectangle.bundleID], concealedInLayout: [])
        #expect(knownQuit.updatesConcealment)
        #expect(knownQuit.graces.isEmpty)
        let unknownQuit = AgentLaunches27.reaction(previous: all, instances: [finder, webKitGPU], known: [], concealedInLayout: [])
        #expect(!unknownQuit.updatesConcealment)
        let helperQuit = AgentLaunches27.reaction(previous: all, instances: [finder, rectangle], known: [], concealedInLayout: [])
        #expect(!helperQuit.updatesConcealment)
    }

    @Test("A login batch starts every grace at once")
    func loginBatch() {
        let first: Instance = ("com.example.b", "/Applications/B.app", .accessory)
        let second: Instance = ("com.example.a", "/Applications/A.app", .accessory)
        let unknown: Instance = ("com.example.new", "/Applications/New.app", .accessory)
        let webKitNetworking: Instance = (
            "com.apple.WebKit.Networking",
            "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc",
            .accessory
        )
        let reaction = AgentLaunches27.reaction(
            previous: [finder.bundleID],
            instances: [finder, first, second, unknown, webKitGPU, webKitNetworking, slackHelper],
            known: [first.bundleID, second.bundleID],
            concealedInLayout: [first.bundleID, second.bundleID]
        )
        #expect(reaction.graces == ["com.example.a", "com.example.b"])
        #expect(reaction.updatesConcealment)
    }

    @Test("Some top-level instance makes an identifier standalone")
    func someInstanceMakesStandalone() {
        let nested: Instance = ("com.example.agent", "/Applications/Host.app/Contents/Library/LoginItems/Agent.app", .accessory)
        let topLevel: Instance = ("com.example.agent", "/Applications/Agent.app", .accessory)
        let reaction = AgentLaunches27.reaction(previous: [finder.bundleID], instances: [finder, nested, topLevel], known: [], concealedInLayout: [])
        #expect(reaction.updatesConcealment)
        let onlyNested = AgentLaunches27.reaction(previous: [finder.bundleID], instances: [finder, nested], known: [], concealedInLayout: [])
        #expect(!onlyNested.updatesConcealment)
    }

    @Test("The snapshot is the set of running identifiers")
    func snapshotIsTheRunningSet() {
        let reaction = AgentLaunches27.reaction(
            previous: [rectangle.bundleID],
            instances: [finder, webKitGPU, webKitGPU, slackHelper],
            known: [],
            concealedInLayout: []
        )
        #expect(reaction.running == [finder.bundleID, webKitGPU.bundleID, slackHelper.bundleID])
    }
}
