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

    @Test("Waiting returns at once when the event has already happened")
    func eventAlreadyHappened() async {
        let clock = ContinuousClock()
        let start = clock.now
        let happened = await SpacingRelaunch.waitUntil(timeout: .seconds(5)) {}
        #expect(happened)
        #expect(clock.now - start < .seconds(4))
    }

    @Test("Waiting returns as soon as the event happens")
    func eventHappensLater() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let yielder = Task {
            try? await Task.sleep(for: .milliseconds(20))
            continuation.yield()
            continuation.finish()
        }
        let clock = ContinuousClock()
        let start = clock.now
        let happened = await SpacingRelaunch.waitUntil(timeout: .seconds(30)) {
            for await _ in stream {
                return
            }
        }
        await yielder.value
        #expect(happened)
        #expect(clock.now - start < .seconds(5))
    }

    @Test("Waiting gives up at the timeout")
    func waitingGivesUpAtTheTimeout() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let happened = await SpacingRelaunch.waitUntil(timeout: .milliseconds(50)) {
            for await _ in stream {
                return
            }
        }
        continuation.finish()
        #expect(!happened)
    }

    @Test("A cancelled wait returns at once")
    func cancelledWaitReturnsAtOnce() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let clock = ContinuousClock()
        let start = clock.now
        let wait = Task {
            await SpacingRelaunch.waitUntil(timeout: .seconds(30)) {
                for await _ in stream {
                    return
                }
            }
        }
        wait.cancel()
        let happened = await wait.value
        continuation.finish()
        #expect(!happened)
        #expect(clock.now - start < .seconds(5))
    }

    @Test("An app gets 10 seconds to quit")
    func quitTimeoutIsTenSeconds() {
        #expect(SpacingRelaunch.quitTimeout == .seconds(10))
    }

    @Test("No offset removes the spacing preferences")
    func noOffsetRemovesThePreferences() {
        #expect(SpacingRelaunch.spacingPreferenceValue(forOffset: 0) == nil)
    }

    @Test("An offset is added to macOS's default")
    func offsetIsAddedToTheDefault() {
        #expect(SpacingRelaunch.spacingPreferenceValue(forOffset: 4) == 20)
        #expect(SpacingRelaunch.spacingPreferenceValue(forOffset: -8) == 8)
    }

    @Test("Both spacing keys are written")
    func bothSpacingKeysAreWritten() {
        #expect(SpacingRelaunch.spacingPreferenceKeys == ["NSStatusItemSpacing", "NSStatusItemSelectionPadding"])
        #expect(SpacingRelaunch.defaultSpacing == 16)
    }
}
