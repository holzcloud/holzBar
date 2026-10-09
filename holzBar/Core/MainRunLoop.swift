//
//  MainRunLoop.swift
//  holzBar
//

import Foundation

/// Runs main-actor work from the main run loop instead of from the current task.
///
/// Every main-actor task runs as a job of the main dispatch queue. A nested run loop
/// started inside such a job, as a modal alert's `runModal()` starts one, does not serve
/// the main queue, so every other main-actor job waits until it ends: an open alert paused
/// hovering, the holzBar Shelf and concealment, and on macOS 27 held back clicks on the
/// clock, battery, Wi-Fi and Control Centre. A nested run loop started from a run loop
/// block does serve the main queue (probed on macOS 26.7.1).
enum MainRunLoop {
    /// Runs the given work on the main thread from the main run loop's default mode and
    /// returns its result once it finishes.
    ///
    /// The caller is suspended, not blocked, and the main actor goes on serving other
    /// tasks while the work runs a nested run loop. The default mode keeps queued work from
    /// starting inside another modal, a menu or a drag. Cancelling the caller does not
    /// cancel the work; the caller still gets its result.
    static func run<Value: Sendable>(_ work: @escaping @MainActor @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    continuation.resume(returning: work())
                }
            }
            // A block added to a run loop does not wake it up by itself.
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
}
