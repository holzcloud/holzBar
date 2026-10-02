import Foundation
import Testing
@testable import HolzBarCore

@Suite("SpacingRelaunch")
struct SpacingRelaunchTests {
    typealias Owner = SpacingRelaunch.Owner

    @Test("A skipped owner does not stop the others")
    func skippedOwnerDoesNotStopTheOthers() {
        let owners = [
            Owner(pid: 10, bundleIdentifier: "com.apple.controlcenter"),
            Owner(pid: 20, bundleIdentifier: "com.example.first"),
            Owner(pid: 30, bundleIdentifier: "com.holzcloud.holzBar"),
            Owner(pid: 40, bundleIdentifier: "com.example.second"),
        ]
        #expect(SpacingRelaunch.processesToRelaunch(owners: owners, ownPID: 30) == [20, 40])
    }

    @Test("holzBar itself is never relaunched")
    func ownProcessIsNeverRelaunched() {
        let owners = [
            Owner(pid: 30, bundleIdentifier: "com.example.renamed"),
            Owner(pid: 31, bundleIdentifier: nil),
            Owner(pid: 50, bundleIdentifier: "com.example.app"),
        ]
        #expect(SpacingRelaunch.processesToRelaunch(owners: owners, ownPID: 30) == [31, 50])
        #expect(SpacingRelaunch.processesToRelaunch(owners: owners, ownPID: 31) == [30, 50])
    }

    @Test("Control Center and MenuBarAgent are never relaunched")
    func systemProcessesAreNeverRelaunched() {
        let owners = [
            Owner(pid: 5, bundleIdentifier: "com.apple.MenuBarAgent"),
            Owner(pid: 6, bundleIdentifier: "com.apple.controlcenter"),
            Owner(pid: 7, bundleIdentifier: "com.apple.Spotlight"),
        ]
        #expect(SpacingRelaunch.processesToRelaunch(owners: owners, ownPID: 1) == [7])
    }

    @Test("Each process is returned once, sorted by pid")
    func distinctAndSorted() {
        let owners = [
            Owner(pid: 90, bundleIdentifier: "com.example.c"),
            Owner(pid: 20, bundleIdentifier: "com.example.a"),
            Owner(pid: 90, bundleIdentifier: "com.example.c"),
            Owner(pid: 40, bundleIdentifier: "com.example.b"),
            Owner(pid: 20, bundleIdentifier: "com.example.a"),
        ]
        #expect(SpacingRelaunch.processesToRelaunch(owners: owners, ownPID: 1) == [20, 40, 90])
    }

    @Test("An owner without a bundle identifier is still returned")
    func ownerWithoutBundleIdentifier() {
        let owners = [
            Owner(pid: 12, bundleIdentifier: nil),
            Owner(pid: 11, bundleIdentifier: "com.example.app"),
        ]
        #expect(SpacingRelaunch.processesToRelaunch(owners: owners, ownPID: 1) == [11, 12])
    }
}
