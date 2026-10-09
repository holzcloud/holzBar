//
//  BlockingWork.swift
//  holzBar
//

import Dispatch
import os.lock

/// Runs work that blocks its thread without blocking the caller.
///
/// A `nonisolated` async function runs on the actor of whoever awaits it
/// (`NonisolatedNonsendingByDefault`, part of approachable concurrency), and so does the
/// body of a continuation it creates. A synchronous call made there from the main actor
/// blocks the main thread. holzBar 0.0.6 asked the menu bar item service that way, and the
/// service, to find the application of holzBar's own items, asks holzBar through
/// Accessibility, which AppKit answers on the main thread: both waited until Accessibility
/// gave up, holzBar never recognised its own section dividers on macOS 26, and the layout
/// settings and the holzBar Shelf stayed on "Loading menu bar items…".
nonisolated enum BlockingWork {
    /// Runs the given work on the given queue and returns its result once it finishes.
    ///
    /// The caller is suspended, not blocked: the main actor goes on serving events while
    /// the work runs. The work runs off the Swift concurrency pool as well, which must not
    /// be blocked either.
    static func run<Value: Sendable>(
        on queue: DispatchQueue,
        _ work: @escaping @Sendable () -> Value
    ) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }

    /// Runs the given work on the given queue and returns its result, or the fallback once
    /// the timeout has passed, whichever comes first.
    ///
    /// The bounded variant of ``run(on:_:)``, for work that may never return. On a timeout
    /// the caller gets the fallback at once, but the work cannot be cancelled: it goes on
    /// blocking the queue's thread until it returns. A caller that must not queue behind the
    /// stuck work has to send later work to another queue, as the item image cache does.
    ///
    /// The work and a timer race for the continuation; the first one resumes it, and the
    /// other finds it gone and does nothing.
    static func run<Value: Sendable>(
        on queue: DispatchQueue,
        timeout: Duration,
        fallback: Value,
        _ work: @escaping @Sendable () -> Value
    ) async -> (value: Value, timedOut: Bool) {
        await withCheckedContinuation { continuation in
            let pending = OSAllocatedUnfairLock<CheckedContinuation<(value: Value, timedOut: Bool), Never>?>(
                initialState: continuation
            )
            let takeContinuation: @Sendable () -> CheckedContinuation<(value: Value, timedOut: Bool), Never>? = {
                pending.withLock { pending in
                    defer { pending = nil }
                    return pending
                }
            }
            queue.async {
                let value = work()
                takeContinuation()?.resume(returning: (value, false))
            }
            // Not cancelled when the work wins (`DispatchWorkItem` is not Sendable): the
            // timer then finds the continuation gone and does nothing.
            let (seconds, attoseconds) = timeout.components
            let nanoseconds = seconds * 1_000_000_000 + attoseconds / 1_000_000_000
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
                takeContinuation()?.resume(returning: (fallback, true))
            }
        }
    }
}
