import Foundation
import os
import Testing
@testable import HolzBarCore

@Suite("Task timeout")
struct TaskTimeoutTests {
    /// How long past its timeout a test lets the helper take to return. A timer that fires on time still resumes its waiter
    /// only when a thread of the Swift concurrency pool is free, and in a full run that is busy with the other suites for a
    /// second or more even with the heavy simulation tests gated (`HeavyTestGate`). The bound stays far below what a helper
    /// that waits for the operation takes (`operationHangs`), so it still tells the two apart.
    private static let slack = Duration.seconds(10)

    /// How long the operation that ignores cancellation is held before the test frees it itself.
    private static let operationHangs = Duration.seconds(30)

    /// Holds an operation until the test opens it; opening before the wait lets it pass.
    private final class Gate: Sendable {
        private let state = OSAllocatedUnfairLock<(isOpen: Bool, waiter: CheckedContinuation<Void, Never>?)>(
            initialState: (false, nil)
        )

        /// Waits until the gate opens; the wait ignores cancellation.
        func wait() async {
            await withCheckedContinuation { continuation in
                let isOpen = state.withLock { state in
                    if !state.isOpen {
                        state.waiter = continuation
                    }
                    return state.isOpen
                }
                if isOpen {
                    continuation.resume()
                }
            }
        }

        func open() {
            let waiter = state.withLock { state in
                state.isOpen = true
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume()
        }
    }

    private struct Failure: Error {}

    @Test("An operation that ignores cancellation times out on time")
    func operationIgnoringCancellationTimesOut() async {
        let gate = Gate()
        // Opens the gate even if the timeout never fires, so a broken helper fails the
        // test instead of hanging it.
        let safety = Task {
            try? await Task.sleep(for: Self.operationHangs)
            gate.open()
        }
        defer {
            gate.open()
            safety.cancel()
        }
        let start = ContinuousClock.now
        await #expect(throws: TaskTimeoutError.self) {
            try await Task(timeout: .milliseconds(100)) {
                await gate.wait()
            }.value
        }
        let elapsed = start.duration(to: .now)
        // The old helper waited for the operation (`operationHangs`).
        #expect(elapsed < .milliseconds(100) + Self.slack, "Timed out after \(elapsed)")
    }

    @Test("A result within the timeout is returned")
    func returnsTheResult() async throws {
        let value = try await Task(timeout: .seconds(5)) { 42 }.value
        #expect(value == 42)
    }

    @Test("The operation's error is passed on")
    func passesTheErrorOn() async {
        await #expect(throws: Failure.self) {
            try await Task(timeout: .seconds(5)) { throw Failure() }.value
        }
    }

    @Test("Cancelling the task ends the wait at once")
    func cancellingEndsTheWait() async {
        let gate = Gate()
        defer { gate.open() }
        let task = Task(timeout: .seconds(5)) {
            await gate.wait()
        }
        task.cancel()
        let start = ContinuousClock.now
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(start.duration(to: .now) < Self.slack)
    }

    @Test("A detached task times out too")
    func detachedTimesOut() async {
        let gate = Gate()
        defer { gate.open() }
        let start = ContinuousClock.now
        await #expect(throws: TaskTimeoutError.self) {
            try await Task.detached(timeout: .milliseconds(100)) {
                await gate.wait()
            }.value
        }
        #expect(start.duration(to: .now) < Self.slack)
    }

    @Test("Only the first resume reaches the continuation")
    func resumesOnce() async throws {
        let once = ResumeOnce<Int>()
        let value = try await withCheckedThrowingContinuation { continuation in
            #expect(once.store(continuation))
            #expect(once.resume(with: .success(1)))
            #expect(!once.resume(with: .success(2)))
            #expect(!once.resume(throwing: Failure()))
        }
        #expect(value == 1)
    }

    @Test("An operation that ends with the cancellation's error still times out")
    func timeoutWinsOverTheCancellationError() async {
        // Like the event barriers: cancelling resumes the operation with CancellationError
        // at once, which races the timeout's own resume.
        for _ in 0 ..< 50 {
            let once = ResumeOnce<Void>()
            await #expect(throws: TaskTimeoutError.self) {
                try await Task(timeout: .milliseconds(5)) {
                    try await withTaskCancellationHandler {
                        try await withCheckedThrowingContinuation { continuation in
                            once.store(continuation)
                        }
                    } onCancel: {
                        once.resume(throwing: CancellationError())
                    }
                }.value
            }
        }
    }

    @Test("A claim decides the result before it is delivered")
    func claimDecidesTheResult() async throws {
        let once = ResumeOnce<Int>()
        let value = try await withCheckedThrowingContinuation { continuation in
            #expect(once.store(continuation))
            let claim = once.claim(.success(1))
            #expect(claim != nil)
            #expect(once.claim(.success(2)) == nil)
            #expect(!once.resume(throwing: Failure()))
            claim?.resume()
        }
        #expect(value == 1)
    }

    @Test("A claim before the continuation is stored is kept")
    func keepsAnEarlyClaim() async throws {
        let once = ResumeOnce<Int>()
        once.claim(.success(1))?.resume()
        #expect(!once.resume(with: .success(2)))
        let value = try await withCheckedThrowingContinuation { continuation in
            #expect(!once.store(continuation))
        }
        #expect(value == 1)
    }

    @Test("A resume before the continuation is stored is kept")
    func keepsAnEarlyResume() async {
        let once = ResumeOnce<Int>()
        #expect(!once.resume(throwing: CancellationError()))
        await #expect(throws: CancellationError.self) {
            try await withCheckedThrowingContinuation { continuation in
                #expect(!once.store(continuation))
            }
        }
    }
}
