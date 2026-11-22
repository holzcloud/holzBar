//
//  WidgetReadoutLink.swift
//  holzBar
//

import Foundation

/// The widgets' consumer of the shared ``SystemMonitor`` (D-01).
///
/// ``WidgetRefreshPolicy`` says when a sampled widget is visible; the host hands that on here as
/// a register or an unregister. The monitor delivers a sample to each registered widget on the
/// widget's own interval, and this turns it into a ``WidgetReading``. A load is the difference of
/// two readings, so every widget has its own ``ReadoutBaseline``: two widgets with different
/// intervals each measure from their own previous sample, and a widget that stops being visible
/// loses its baseline and its last reading, so a reveal never shows an average over the hidden
/// time or an old value (D-13).
@MainActor
final class WidgetReadoutLink {
    /// The monitor the widgets register with.
    weak var monitor: SystemMonitor?
    /// Called with every new reading of a widget, to draw it.
    var onReading: (@MainActor (UUID, WidgetReading) -> Void)?

    private var baselines = [UUID: ReadoutBaseline]()
    private var readings = [UUID: WidgetReading]()

    /// The consumer id a widget has in the monitor's ledger.
    static func consumerID(for id: UUID) -> String {
        "widget." + id.uuidString
    }

    /// Does what the policy said about the widget's registration.
    func apply(_ change: WidgetRefreshPolicy.ReadoutChange, for definition: WidgetDefinition) {
        let id = definition.id
        switch change {
        case .keep:
            break
        case .register(let request):
            // A new request starts a new baseline: the first reading after it is only the base.
            baselines[id] = ReadoutBaseline()
            readings[id] = nil
            let source = definition.source
            monitor?.register(Self.consumerID(for: id), kind: .visible, request: request) { [weak self] sample in
                self?.receive(sample, source: source, id: id)
            }
        case .unregister:
            forget(id)
        }
    }

    /// The last reading the monitor delivered for the widget; `nil` before the first one.
    func lastReading(for id: UUID) -> WidgetReading? {
        readings[id]
    }

    /// Drops the widget's baseline and its last reading: the next delivery is a baseline again.
    func resetBaseline(for id: UUID) {
        guard baselines[id] != nil else {
            return
        }
        baselines[id] = ReadoutBaseline()
        readings[id] = nil
    }

    /// Unregisters the widget and drops everything kept for it.
    func forget(_ id: UUID) {
        monitor?.unregister(Self.consumerID(for: id))
        baselines[id] = nil
        readings[id] = nil
    }

    private func receive(_ sample: ReadoutSample, source: WidgetSource, id: UUID) {
        guard var baseline = baselines[id] else {
            return
        }
        let reading: WidgetReading
        switch source {
        case .cpu:
            guard sample.read.contains(.cpu) else {
                return
            }
            reading = baseline.cpuLoad(sample.cpuTicks).map(WidgetReading.fraction) ?? .unavailable
        default:
            return
        }
        baselines[id] = baseline
        readings[id] = reading
        onReading?(id, reading)
    }
}
