import Foundation
import os
import Testing
@testable import HolzBarCore

@Suite("AsyncLock")
struct AsyncLockTests {
    /// A thread-safe list of events, in the order they happened.
    private final class Recorder: Sendable {
        private let events = OSAllocatedUnfairLock<[String]>(initialState: [])

        func record(_ event: String) {
            events.withLock { $0.append(event) }
        }

        var all: [String] {
            events.withLock { $0 }
        }
    }

    /// Waits until `condition` holds, polling generously; fails after about five seconds.
    private static func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The condition did not become true in time")
    }

    @Test("A free lock is taken at once")
    func freeLockIsTakenAtOnce() async throws {
        let lock = AsyncLock()
        try await lock.lock()
        lock.unlock()
        try await lock.lock()
        lock.unlock()
    }

    @Test("Waiters get the lock in the order they asked")
    func waitersGetTheLockInOrder() async throws {
        let lock = AsyncLock()
        let recorder = Recorder()
        try await lock.lock()

        var tasks: [Task<Void, Error>] = []
        for name in ["first", "second", "third"] {
            let task = Task {
                recorder.record("asked \(name)")
                try await lock.lock()
                recorder.record("got \(name)")
                lock.unlock()
            }
            tasks.append(task)
            // Each task must be waiting before the next one asks.
            try await Self.waitUntil { recorder.all.contains("asked \(name)") }
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(!recorder.all.contains { $0.hasPrefix("got") })
        lock.unlock()
        for task in tasks {
            try await task.value
        }
        let got = recorder.all.filter { $0.hasPrefix("got") }
        #expect(got == ["got first", "got second", "got third"])
    }

    @Test("A cancelled waiter does not take the lock")
    func cancelledWaiterDoesNotTakeTheLock() async throws {
        let lock = AsyncLock()
        let recorder = Recorder()
        try await lock.lock()

        let cancelled = Task {
            recorder.record("asked cancelled")
            do {
                try await lock.lock()
                recorder.record("got cancelled")
                lock.unlock()
            } catch {
                recorder.record(error is CancellationError ? "threw cancelled" : "threw \(error)")
            }
        }
        try await Self.waitUntil { recorder.all.contains("asked cancelled") }
        try await Task.sleep(for: .milliseconds(50))

        let following = Task {
            recorder.record("asked following")
            try await lock.lock()
            recorder.record("got following")
            lock.unlock()
        }
        try await Self.waitUntil { recorder.all.contains("asked following") }
        try await Task.sleep(for: .milliseconds(50))

        cancelled.cancel()
        await cancelled.value
        #expect(recorder.all.contains("threw cancelled"))

        lock.unlock()
        try await following.value
        let events = recorder.all
        #expect(events.contains("got following"))
        #expect(!events.contains("got cancelled"))
    }

    @Test("Holders never overlap")
    func holdersNeverOverlap() async throws {
        let lock = AsyncLock()
        let inUse = OSAllocatedUnfairLock(initialState: false)
        let overlaps = OSAllocatedUnfairLock(initialState: 0)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await lock.lock()
                    defer { lock.unlock() }
                    let wasInUse = inUse.withLock { value in
                        let previous = value
                        value = true
                        return previous
                    }
                    if wasInUse {
                        overlaps.withLock { $0 += 1 }
                    }
                    await Task.yield()
                    try await Task.sleep(for: .milliseconds(1))
                    inUse.withLock { $0 = false }
                }
            }
            try await group.waitForAll()
        }

        let count = overlaps.withLock { $0 }
        #expect(count == 0)
    }
}
