//
//  CoalescedRun.swift
//  holzBar
//

/// Runs an operation for batches of elements, one batch at a time.
///
/// A request while a batch runs adds its elements to the next batch and waits until the
/// run ends, so at most one batch runs and at most one waits, however many requests
/// arrive. The operation of the request that starts a run performs every batch of that
/// run, so the callers pass the same operation.
@MainActor
final class CoalescedRun<Element: Hashable & Sendable> {
    /// The elements of the next batch.
    private(set) var pending = Set<Element>()

    /// The task that runs the batches until none is pending.
    private var task: Task<Void, Never>?

    /// Whether a run is in progress.
    var isRunning: Bool {
        task != nil
    }

    /// Creates a coalesced run.
    nonisolated init() {}

    /// Runs the operation for the given elements, together with those of every request
    /// that arrives meanwhile, and returns once they have run.
    func run(_ elements: some Sequence<Element>, operation: @escaping @MainActor (Set<Element>) async -> Void) async {
        pending.formUnion(elements)
        if let task {
            await task.value
            return
        }
        guard !pending.isEmpty else {
            return
        }
        let task = Task {
            while !pending.isEmpty {
                let batch = pending
                pending.removeAll()
                await operation(batch)
            }
            // In the same synchronous step as the last check, so no request slips between.
            self.task = nil
        }
        self.task = task
        await task.value
    }
}
