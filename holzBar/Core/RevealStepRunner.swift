//
//  RevealStepRunner.swift
//  holzBar
//

import Foundation

/// Applies a ``RevealAnimationSchedule`` one step at a time, on the main actor.
///
/// A task exists only while a movement runs (about 0.18 s). There is no timer, no display
/// link and no observer outside that window. Starting a run cancels the one before it, and
/// a cancelled run calls neither `apply` nor `finish` again, so a quick show and hide never
/// queue; the caller applies the end state of the new change itself.
@MainActor
final class RevealStepRunner {
    /// The task that sleeps between the steps, while a run is going.
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    /// Runs the schedule.
    ///
    /// - Parameters:
    ///   - schedule: The steps. An instant schedule calls `finish` at once.
    ///   - apply: Called with each step's length at its time.
    ///   - finish: Called once after the last step, unless the run was cancelled.
    func run(
        _ schedule: RevealAnimationSchedule,
        apply: @escaping @MainActor (Double) -> Void,
        finish: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = nil
        guard !schedule.isInstant else {
            finish()
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        task = Task {
            for step in schedule.steps {
                do {
                    try await clock.sleep(until: start.advanced(by: .seconds(step.time)), tolerance: .milliseconds(2))
                } catch {
                    return
                }
                // A sleep that had already finished does not throw when the task is cancelled.
                guard !Task.isCancelled else {
                    return
                }
                apply(step.length)
            }
            guard !Task.isCancelled else {
                return
            }
            finish()
        }
    }

    /// Stops the running movement; its remaining steps and its `finish` never happen.
    func cancel() {
        task?.cancel()
        task = nil
    }
}
