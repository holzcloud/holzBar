import Dispatch
import Foundation
import Testing
@testable import HolzBarCore

/// The menu bar item service answers holzBar's synchronous XPC requests, and to answer
/// one it may ask holzBar itself through Accessibility, which AppKit serves on the main
/// thread. holzBar 0.0.6 made the requests on the main thread, so the two waited for each
/// other until Accessibility gave up, and holzBar never recognised its own items on
/// macOS 26 ("Loading menu bar items…"). These tests run with the app's concurrency
/// settings, under which a `nonisolated` async function runs on its caller's actor.
@MainActor
@Suite("BlockingWork")
struct BlockingWorkTests {
    /// The queue the blocking work runs on.
    private let queue = DispatchQueue(label: "BlockingWorkTests")

    @Test("Blocking work awaited on the main actor runs off the main thread")
    func runsOffTheMainThread() async {
        let ranOnMainThread = await BlockingWork.run(on: queue) {
            pthread_main_np() != 0
        }
        #expect(!ranOnMainThread)
    }

    @Test("The main actor stays free while the work waits for it")
    func mainActorAnswersWhileWorkWaits() async {
        // The work waits for the main actor, as the service waits for holzBar's main thread
        // while holzBar waits for the service's reply. Work run on the main thread would
        // keep this task from running and time out.
        let answered = DispatchSemaphore(value: 0)
        Task { @MainActor in
            answered.signal()
        }
        let mainActorAnswered = await BlockingWork.run(on: queue) {
            answered.wait(timeout: .now() + 2) == .success
        }
        #expect(mainActorAnswered)
    }

    @Test("The work's result is returned", arguments: [0, 1, 42])
    func returnsTheResult(value: Int) async {
        let result = await BlockingWork.run(on: queue) { value }
        #expect(result == value)
    }

    // MARK: Bounded

    // An item image capture on macOS 26 can block its thread forever (F-13). The bounded
    // variant gives the caller a fallback after the timeout; the work goes on blocking its
    // queue, which is why later work has to go to another one.

    @Test("Work that finishes in time returns its value")
    func boundedReturnsTheValue() async {
        let result = await BlockingWork.run(on: queue, timeout: .seconds(2), fallback: -1) { 7 }
        #expect(result.value == 7)
        #expect(!result.timedOut)
    }

    @Test("Work that blocks past the timeout returns the fallback on time")
    func boundedReturnsTheFallbackOnTime() async {
        let blocker = DispatchSemaphore(value: 0)
        defer { blocker.signal() }
        let start = ContinuousClock.now
        let result = await BlockingWork.run(on: queue, timeout: .milliseconds(100), fallback: -1) {
            blocker.wait()
            return 1
        }
        let elapsed = start.duration(to: .now)
        #expect(result.value == -1)
        #expect(result.timedOut)
        // Slack for shared CI runners, as in the task timeout tests.
        #expect(elapsed < .milliseconds(100) + .milliseconds(400), "Returned after \(elapsed)")
    }

    @Test("A late completion does not resume the caller twice")
    func lateCompletionResumesOnce() async {
        let blocker = DispatchSemaphore(value: 0)
        let result = await BlockingWork.run(on: queue, timeout: .milliseconds(100), fallback: -1) {
            blocker.wait()
            return 1
        }
        #expect(result.timedOut)
        blocker.signal()
        // The queue is serial, so this runs only after the late work finished and tried to
        // resume; a second resume would trap the test process.
        let next = await BlockingWork.run(on: queue) { 2 }
        #expect(next == 2)
    }

    @Test("Work on a fresh queue runs while the old one is blocked")
    func freshQueueRuns() async {
        let blocker = DispatchSemaphore(value: 0)
        defer { blocker.signal() }
        let stuck = await BlockingWork.run(on: queue, timeout: .milliseconds(100), fallback: -1) {
            blocker.wait()
            return 1
        }
        #expect(stuck.timedOut)
        let freshQueue = DispatchQueue(label: "BlockingWorkTests.fresh")
        let result = await BlockingWork.run(on: freshQueue, timeout: .seconds(2), fallback: -1) { 5 }
        #expect(result.value == 5)
        #expect(!result.timedOut)
    }
}
