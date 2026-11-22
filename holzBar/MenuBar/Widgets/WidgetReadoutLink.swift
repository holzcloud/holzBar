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
        case .networkSpeed:
            guard sample.read.contains(.network) else {
                return
            }
            // A missing or impossible rate (the first sample, a counter that went backwards, a gap
            // over 300 s) is the en dash, never an old value (MON-09).
            reading = baseline.networkRates(sample.network).map {
                WidgetReading.rates(first: $0.first, second: $0.second)
            } ?? .unavailable
        case .diskActivity:
            guard sample.read.contains(.diskActivity) else {
                return
            }
            reading = baseline.diskRates(sample.disk).map {
                WidgetReading.rates(first: $0.first, second: $0.second)
            } ?? .unavailable
        default:
            return
        }
        baselines[id] = baseline
        readings[id] = reading
        onReading?(id, reading)
    }
}

/// The unit symbols and labels of the readout texts in the user's language (D-08, UI contract
/// "Rates"). Core makes the numbers; the app supplies the words, so Core needs no catalog.
extension ReadoutTexts {
    private static var cache = [String: ReadoutTexts]()

    /// The texts for the locale, made once per locale. The unit symbols come from the system's
    /// abbreviations for kilo, mega and giga bytes and bits in that locale; the labels come from
    /// the string catalog. The words of the other readouts stay English until the plans that show
    /// them localize them.
    static func localized(locale: Locale) -> ReadoutTexts {
        let key = locale.identifier
        if let cached = cache[key] {
            return cached
        }
        let formatter = MeasurementFormatter()
        formatter.locale = locale
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        func symbols(_ units: [UnitInformationStorage], fallback: [String]) -> [String] {
            zip(units, fallback).map { unit, fallback in
                let symbol = formatter.string(from: unit)
                return symbol.isEmpty ? fallback : symbol
            }
        }
        var texts = ReadoutTexts.english
        texts.byteSymbols = symbols([.kilobytes, .megabytes, .gigabytes], fallback: english.byteSymbols)
        texts.bitSymbols = symbols([.kilobits, .megabits, .gigabits], fallback: english.bitSymbols)
        texts.perSecondFormat = String(localized: "%@/s")
        texts.readFormat = String(localized: "R %@")
        texts.writeFormat = String(localized: "W %@")
        cache[key] = texts
        return texts
    }
}
