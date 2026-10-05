import Foundation
import Testing
@testable import HolzBarCore

/// A modal alert run from a main-actor task starts a nested run loop inside a job of the
/// main dispatch queue, which does not serve that queue, so all other main-actor work
/// waited until the alert closed; on macOS 27 even clicks on the clock, battery, Wi-Fi and
/// Control Centre were held back. Work run through `MainRunLoop` starts from the main run
/// loop instead, and its nested run loop lets main-actor tasks run.
@MainActor
@Suite("MainRunLoop", .serialized, .timeLimit(.minutes(1)))
struct MainRunLoopTests {
    /// A flag that a main-actor task sets.
    @MainActor
    private final class Flag {
        var isSet = false
    }

    @Test("The work runs on the main thread, from the main run loop's default mode")
    func runsFromTheMainRunLoop() async {
        let (isMainThread, mode) = await MainRunLoop.run {
            (Thread.isMainThread, RunLoop.current.currentMode)
        }
        #expect(isMainThread)
        #expect(mode == .default)
    }

    @Test("Main-actor tasks run while the work runs a nested run loop")
    func mainActorTasksRunInsideNestedRunLoop() async {
        let ranInside = await MainRunLoop.run {
            let flag = Flag()
            Task { @MainActor in
                flag.isSet = true
            }
            // A nested run loop, as a modal alert runs one.
            let deadline = Date(timeIntervalSinceNow: 0.3)
            while !flag.isSet, Date() < deadline {
                RunLoop.current.run(mode: .default, before: min(deadline, Date(timeIntervalSinceNow: 0.01)))
            }
            return flag.isSet
        }
        #expect(ranInside)
    }

    @Test("The work's result is returned", arguments: [0, 1, 42])
    func returnsTheResult(value: Int) async {
        let result = await MainRunLoop.run { value }
        #expect(result == value)
    }
}
