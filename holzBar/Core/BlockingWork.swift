//
//  BlockingWork.swift
//  holzBar
//

import Dispatch

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
}
