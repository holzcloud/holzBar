//
//  HeavyTestGate.swift
//  holzBar
//

import Foundation

/// Keeps the heavy, synchronous simulation tests from starving the Swift concurrency pool.
///
/// Swift Testing runs every test case as a task, and a synchronous test body keeps its pool thread busy until it returns.
/// The pool has one thread per core, and the simulation, catalogue, exhaustive and fuzz tests have many cases that each
/// compute for seconds; started together they hold every pool thread for minutes. A test that only awaits (the timing
/// tests of `BlockingWork`, `SpacingRelaunch` and `Task timeout`) then cannot continue until a heavy case ends: its clock
/// runs on while it waits for a thread, and `elapsed < 500 ms` fails with a reported duration of about 270 seconds even
/// though the code under test is fast.
///
/// A heavy test runs its body through `run`, which lets at most half of the cores compute at the same time. The other
/// cases wait suspended, which holds no thread, so the rest of the pool stays free for the tests that wait on timers.
actor HeavyTestGate {
    static let shared = HeavyTestGate(width: max(1, ProcessInfo.processInfo.activeProcessorCount / 2))

    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(width: Int) {
        free = width
    }

    /// Runs `body` once fewer than the gate's width of heavy bodies are running.
    static func run<T, E: Error>(_ body: () throws(E) -> T) async throws(E) -> T {
        await shared.acquire()
        let result = Result(catching: body)
        await shared.release()
        return try result.get()
    }

    private func acquire() async {
        if free > 0 {
            free -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func release() {
        if waiters.isEmpty {
            free += 1
        } else {
            // The slot goes straight to the next waiter.
            waiters.removeFirst().resume()
        }
    }
}
