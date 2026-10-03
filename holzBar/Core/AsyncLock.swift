//
//  AsyncLock.swift
//  holzBar
//

import os

/// A first-in, first-out lock for async code that respects task cancellation.
///
/// holzBar uses it to serialise the posting of menu bar item move and click
/// events, so two moves never overlap. It replaces the `AsyncSemaphore` of the
/// Semaphore package (`waitUnlessCancelled()` and `signal()`):
///
/// ```swift
/// try await lock.lock()
/// defer { lock.unlock() }
/// ```
///
/// A task that is cancelled while it waits leaves the queue and its `lock()`
/// throws `CancellationError`. A task that was already handed the lock when it
/// was cancelled keeps it and unlocks as usual, so the lock never leaks.
final class AsyncLock: Sendable {
    private struct Waiter {
        let id: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var isLocked = false
        var nextID: UInt64 = 0
        var waiters: [Waiter] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Creates an unlocked lock.
    init() {}

    /// Takes the lock, waiting in line behind earlier callers.
    ///
    /// - Throws: `CancellationError` when the task is cancelled before it gets the lock.
    func lock() async throws {
        try Task.checkCancellation()
        let id: UInt64? = state.withLock { state in
            if !state.isLocked {
                state.isLocked = true
                return nil
            }
            state.nextID &+= 1
            return state.nextID
        }
        guard let id else {
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let resumeNow: Bool = state.withLock { state in
                    if Task.isCancelled {
                        return true
                    }
                    if !state.isLocked {
                        // The lock was released between the first check and now.
                        state.isLocked = true
                        continuation.resume()
                        return false
                    }
                    state.waiters.append(Waiter(id: id, continuation: continuation))
                    return false
                }
                if resumeNow {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let waiter: Waiter? = state.withLock { state in
                guard let index = state.waiters.firstIndex(where: { $0.id == id }) else {
                    // Not queued yet (the operation sees the cancellation) or already
                    // handed the lock (the caller keeps it and unlocks as usual).
                    return nil
                }
                return state.waiters.remove(at: index)
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Releases the lock, handing it to the first waiter if there is one.
    func unlock() {
        let next: Waiter? = state.withLock { state in
            precondition(state.isLocked, "AsyncLock unlocked while it was not locked")
            if state.waiters.isEmpty {
                state.isLocked = false
                return nil
            }
            return state.waiters.removeFirst()
        }
        next?.continuation.resume()
    }
}
