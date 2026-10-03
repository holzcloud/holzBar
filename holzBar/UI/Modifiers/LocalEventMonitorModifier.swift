//
//  LocalEventMonitorModifier.swift
//  holzBar
//

import SwiftUI

private struct LocalEventMonitorModifier: ViewModifier {
    /// Owns the monitor; the monitor removes itself when the model is released.
    @MainActor
    @Observable
    private final class Model {
        @ObservationIgnored private let monitor: EventMonitor

        init(mask: NSEvent.EventTypeMask, action: @escaping @MainActor (NSEvent) -> NSEvent?) {
            self.monitor = EventMonitor.local(for: mask, handler: action)
        }

        /// Starts or stops the monitor.
        func setEnabled(_ isEnabled: Bool) {
            if isEnabled {
                monitor.start()
            } else {
                monitor.stop()
            }
        }
    }

    @State private var model: Model
    @Binding var isEnabled: Bool

    init(mask: NSEvent.EventTypeMask, isEnabled: Binding<Bool>, action: @escaping @MainActor (NSEvent) -> NSEvent?) {
        self._model = State(wrappedValue: Model(mask: mask, action: action))
        self._isEnabled = isEnabled
    }

    func body(content: Content) -> some View {
        content.onChange(of: isEnabled, initial: true) { _, newValue in
            model.setEnabled(newValue)
        }
    }
}

extension View {
    /// Returns a view that performs the given action when events corresponding
    /// to the given event type mask are received.
    ///
    /// - Parameters:
    ///   - mask: An event type mask specifying which events to monitor.
    ///   - isEnabled: A Boolean value that determines whether the event monitor
    ///     is enabled.
    ///   - action: An action to perform when the event monitor receives events
    ///     corresponding to `mask`.
    func localEventMonitor(
        mask: NSEvent.EventTypeMask,
        isEnabled: Bool = true,
        action: @escaping @MainActor (NSEvent) -> NSEvent?
    ) -> some View {
        modifier(LocalEventMonitorModifier(mask: mask, isEnabled: .constant(isEnabled), action: action))
    }
}
