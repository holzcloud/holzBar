//
//  ConcurrencyHelpers.swift
//  holzBar
//

import Foundation
import os.lock

// MARK: - Task Timeout

/// An error that indicates that a task timed out.
nonisolated struct TaskTimeoutError: CustomStringConvertible, LocalizedError {
    let description = "Task timed out before completion"
    var errorDescription: String? { description }
}

// MARK: - Resume Once

/// A continuation that only the first of several racers resumes.
///
/// A wait that can end in several ways (the awaited work finishes, a timeout fires, the
/// waiting task is cancelled) must resume its continuation exactly once: a second resume
/// traps. Every racer calls ``resume(with:)``; the first one resumes the continuation and
/// every later call does nothing. A result that arrives before the continuation is stored,
/// such as a cancellation of a task that has not started waiting yet, is kept and handed
/// to the continuation as soon as ``store(_:)`` receives it.
nonisolated final class ResumeOnce<Success: Sendable>: Sendable {
    private enum State {
        case waiting(CheckedContinuation<Success, any Error>?)
        case early(Result<Success, any Error>)
        case resumed
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: .waiting(nil))

    init() {}

    /// Stores the continuation to resume.
    ///
    /// - Returns: `true` while the continuation waits for a result; `false` if a result
    ///   arrived first, in which case the continuation has been resumed with it already.
    @discardableResult
    func store(_ continuation: CheckedContinuation<Success, any Error>) -> Bool {
        let early: Result<Success, any Error>? = state.withLock { state in
            switch state {
            case .waiting:
                state = .waiting(continuation)
                return nil
            case .early(let result):
                state = .resumed
                return result
            case .resumed:
                return nil
            }
        }
        guard let early else {
            return true
        }
        continuation.resume(with: early)
        return false
    }

    /// Resumes the stored continuation with the given result, unless a racer came first.
    ///
    /// Without a stored continuation the result is kept for ``store(_:)``.
    ///
    /// - Returns: `true` if this call resumed the continuation.
    @discardableResult
    func resume(with result: Result<Success, any Error>) -> Bool {
        let continuation: CheckedContinuation<Success, any Error>? = state.withLock { state in
            switch state {
            case .waiting(let continuation?):
                state = .resumed
                return continuation
            case .waiting(nil):
                state = .early(result)
                return nil
            case .early, .resumed:
                return nil
            }
        }
        continuation?.resume(with: result)
        return continuation != nil
    }

    /// Resumes the stored continuation with the given error, unless a racer came first.
    ///
    /// - Returns: `true` if this call resumed the continuation.
    @discardableResult
    func resume(throwing error: any Error) -> Bool {
        resume(with: .failure(error))
    }
}

nonisolated extension Task {
    /// Waits for the given task, but no longer than `timeout`.
    ///
    /// When the timeout fires first, the task is cancelled and ``TaskTimeoutError`` is
    /// thrown at once, without waiting for the task to end (an operation that ignores
    /// cancellation goes on in the background and its result is dropped). Cancelling the
    /// waiting task cancels the task and throws `CancellationError`. The task is created by
    /// the caller from the operation, so the operation is handed over exactly once.
    ///
    /// - Parameters:
    ///   - operationTask: The task to wait for.
    ///   - timeout: The duration the task must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///
    /// - Returns: The result of the task, if successful.
    fileprivate static func value<C: Clock>(
        of operationTask: Task<Success, any Error>,
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration?,
        clock: C
    ) async throws -> Success {
        let outcome = ResumeOnce<Success>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                outcome.store(continuation)
                let sleeper = _Concurrency.Task<Void, Never> {
                    do {
                        try await _Concurrency.Task<Never, Never>.sleep(for: timeout, tolerance: tolerance, clock: clock)
                    } catch {
                        return
                    }
                    // Cancel before resuming: the operation's cancellation handlers then run
                    // (and its clean-up is enqueued on its actor) before the caller goes on.
                    operationTask.cancel()
                    outcome.resume(throwing: TaskTimeoutError())
                }
                _Concurrency.Task<Void, Never> {
                    let result = await operationTask.result
                    outcome.resume(with: result)
                    sleeper.cancel()
                }
            }
        } onCancel: {
            operationTask.cancel()
            outcome.resume(throwing: _Concurrency.CancellationError())
        }
    }
}

nonisolated extension Task where Failure == any Error {
    /// Runs the given throwing operation asynchronously as part of a
    /// new _unstructured_ top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown at once,
    /// even if the operation ignores cancellation.
    ///
    /// - Parameters:
    ///   - timeout: The duration the operation must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///   - name: Human readable name of the task.
    ///   - priority: The priority of the operation.
    ///   - operation: The operation to perform.
    @discardableResult
    init<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        name: String? = nil,
        priority: TaskPriority? = nil,
        @_inheritActorContext @_implicitSelfCapture
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) {
        let operationTask = Task<Success, any Error>(name: name, priority: priority, operation: operation)
        self.init(name: name, priority: priority) {
            try await Task.value(of: operationTask, timeout: timeout, tolerance: tolerance, clock: clock)
        }
    }

    /// Runs the given throwing operation asynchronously as part of a
    /// new _unstructured_ _detached_ top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown at once,
    /// even if the operation ignores cancellation.
    ///
    /// - Parameters:
    ///   - timeout: The duration the operation must complete within.
    ///   - tolerance: The precision threshold of the timeout operation.
    ///   - clock: The clock that manages the timeout operation.
    ///   - name: Human readable name of the task.
    ///   - priority: The priority of the operation.
    ///   - operation: The operation to perform.
    ///
    /// - Returns: A reference to the task.
    @discardableResult
    static func detached<C: Clock>(
        timeout: C.Instant.Duration,
        tolerance: C.Instant.Duration? = nil,
        clock: C = .continuous,
        name: String? = nil,
        priority: TaskPriority? = nil,
        operation: sending @escaping @isolated(any) () async throws -> Success
    ) -> Task<Success, Failure> {
        let operationTask = Task<Success, any Error>.detached(name: name, priority: priority, operation: operation)
        return detached(name: name, priority: priority) {
            try await value(of: operationTask, timeout: timeout, tolerance: tolerance, clock: clock)
        }
    }
}
