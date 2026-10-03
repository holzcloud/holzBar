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

nonisolated extension Task {
    /// Waits for the given task alongside a timeout operation in a structured
    /// task group.
    ///
    /// If the task does not complete within the provided duration, the timeout
    /// operation cancels the group, which cancels the task, and throws a
    /// ``TaskTimeoutError``. The task is created by the caller from the operation,
    /// so the operation is handed over exactly once.
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
        try await withThrowingTaskGroup(of: Success.self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await operationTask.value
                } onCancel: {
                    operationTask.cancel()
                }
            }
            group.addTask {
                try await _Concurrency.Task.sleep(for: timeout, tolerance: tolerance, clock: clock)
                throw TaskTimeoutError()
            }
            guard let success = try await group.next() else {
                throw _Concurrency.CancellationError()
            }
            group.cancelAll()
            return success
        }
    }
}

nonisolated extension Task where Failure == any Error {
    /// Runs the given throwing operation asynchronously as part of a
    /// new _unstructured_ top-level task.
    ///
    /// If the operation does not complete within the provided duration,
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown.
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
    /// the task is cancelled and a ``TaskTimeoutError`` is thrown.
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
