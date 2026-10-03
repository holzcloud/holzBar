//
//  ObservationLoop.swift
//  holzBar
//

import Observation

/// Reports every change of a value that is read from `@Observable` models.
///
/// SwiftUI views follow `@Observable` models on their own. Code outside a view, such as
/// one model reacting to another, uses this loop instead of Combine's `$property.sink`.
/// `withObservationTracking` reports only the first change after it is armed, and it
/// reports it before the new value is stored, on the thread that changes it. So the loop
/// hops to the main actor, reads the new value there, reports it and arms itself again.
/// Several changes in one turn of the main actor are reported once, with the last value.
///
/// It works on macOS 14; the `Observations` sequence of macOS 26 is not needed.
///
/// ```swift
/// let loop = ObservationLoop.observe { settings.showOnHover } onChange: { isOn in
///     monitors.update(isOn)
/// }
/// ```
///
/// The loop stops when it is cancelled or released.
@MainActor
final class ObservationLoop {
    /// Reads the value again, re-arms the tracking and reports the value.
    private var reportChange: (@MainActor () -> Void)?

    /// Starts observing the value that `value` reads.
    ///
    /// - Parameters:
    ///   - value: Reads the observed value from `@Observable` models.
    ///   - onChange: Called on the main actor with the new value after each change.
    init<Value>(
        observing value: @escaping @MainActor () -> Value,
        onChange: @escaping @MainActor (Value) -> Void
    ) {
        reportChange = { [weak self] in
            guard let self else {
                return
            }
            onChange(track(value))
        }
        _ = track(value)
    }

    /// Starts observing the value that `value` reads and returns the loop.
    static func observe<Value>(
        _ value: @escaping @MainActor () -> Value,
        onChange: @escaping @MainActor (Value) -> Void
    ) -> ObservationLoop {
        ObservationLoop(observing: value, onChange: onChange)
    }

    /// Starts observing an equatable value and returns the loop; like Combine's
    /// `removeDuplicates()`, a change that leaves the value equal is not reported.
    ///
    /// `@Observable` reports every assignment, even one of the same value.
    static func observe<Value: Equatable>(
        _ value: @escaping @MainActor () -> Value,
        onChange: @escaping @MainActor (Value) -> Void
    ) -> ObservationLoop {
        let last = LastValue(value())
        return ObservationLoop(observing: value) { newValue in
            guard newValue != last.value else {
                return
            }
            last.value = newValue
            onChange(newValue)
        }
    }

    /// Stops the loop; no change is reported after this.
    func cancel() {
        reportChange = nil
    }

    /// Reads the value while tracking which properties it reads, and arms the loop for the
    /// next change of any of them.
    private func track<Value>(_ value: @MainActor () -> Value) -> Value {
        withObservationTracking {
            value()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reportChange?()
            }
        }
    }
}

/// The last value an observation of an equatable value reported.
@MainActor
private final class LastValue<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
