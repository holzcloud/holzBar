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
}
