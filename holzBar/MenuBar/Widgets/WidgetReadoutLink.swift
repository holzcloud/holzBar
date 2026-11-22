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
    /// What each widget was last delivered, so a change of its format (memory in percent or in
    /// gigabytes) shows its new text at once instead of waiting for the next delivery.
    private var samples = [UUID: ReadoutSample]()
    /// The definition each widget has now: the delivery turns into a reading by its format.
    private var definitions = [UUID: WidgetDefinition]()

    /// The consumer id a widget has in the monitor's ledger.
    static func consumerID(for id: UUID) -> String {
        "widget." + id.uuidString
    }

    /// Does what the policy said about the widget's registration.
    func apply(_ change: WidgetRefreshPolicy.ReadoutChange, for definition: WidgetDefinition) {
        let id = definition.id
        definitions[id] = definition
        switch change {
        case .keep:
            rebuildReading(for: definition)
        case .register(let request):
            // A new request starts a new baseline: the first reading after it is only the base.
            baselines[id] = ReadoutBaseline()
            readings[id] = nil
            samples[id] = nil
            monitor?.register(Self.consumerID(for: id), kind: .visible, request: request) { [weak self] sample in
                self?.receive(sample, id: id)
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
        samples[id] = nil
        definitions[id] = nil
    }

    /// Makes the reading of a widget whose format changed from the last delivery. Only the
    /// memory and the free disk space are a value of one sample; a rate needs its baseline.
    private func rebuildReading(for definition: WidgetDefinition) {
        let id = definition.id
        guard
            readings[id] == nil, definition.source == .memory || definition.source == .freeDisk,
            let sample = samples[id], var baseline = baselines[id],
            let reading = Self.reading(from: sample, definition: definition, baseline: &baseline)
        else {
            return
        }
        baselines[id] = baseline
        readings[id] = reading
    }

    private func receive(_ delivered: ReadoutSample, id: UUID) {
        guard var baseline = baselines[id], let definition = definitions[id] else {
            return
        }
        // An event sample (the memory pressure) carries one metric; the kept sample holds them all.
        let sample = samples[id]?.merging(delivered) ?? delivered
        guard let reading = Self.reading(from: delivered, definition: definition, baseline: &baseline) else {
            return
        }
        samples[id] = sample
        baselines[id] = baseline
        readings[id] = reading
        onReading?(id, reading)
    }

    /// The reading a sample gives a widget, or `nil` when the sample does not carry the metric
    /// the widget's format reads (it is not for this widget, so nothing changes).
    private static func reading(
        from sample: ReadoutSample,
        definition: WidgetDefinition,
        baseline: inout ReadoutBaseline
    ) -> WidgetReading? {
        switch definition.source {
        case .cpu:
            guard sample.read.contains(.cpu) else {
                return nil
            }
            return baseline.cpuLoad(sample.cpuTicks).map(WidgetReading.fraction) ?? .unavailable
        case .networkSpeed:
            guard sample.read.contains(.network) else {
                return nil
            }
            // A missing or impossible rate (the first sample, a counter that went backwards, a gap
            // over 300 s) is the en dash, never an old value (MON-09).
            return baseline.networkRates(sample.network).map {
                WidgetReading.rates(first: $0.first, second: $0.second)
            } ?? .unavailable
        case .diskActivity:
            guard sample.read.contains(.diskActivity) else {
                return nil
            }
            return baseline.diskRates(sample.disk).map {
                WidgetReading.rates(first: $0.first, second: $0.second)
            } ?? .unavailable
        case .memory:
            return memoryReading(from: sample, preset: definition.preset)
        case .freeDisk:
            guard sample.read.contains(.diskSpace) else {
                return nil
            }
            return diskSpaceReading(sample.diskSpace, preset: definition.preset)
        case .dateTime, .battery, .uptime, .countdown:
            return nil
        }
    }

    private static func memoryReading(from sample: ReadoutSample, preset: WidgetPreset) -> WidgetReading? {
        switch preset {
        case .pressure:
            guard sample.read.contains(.memoryPressure) else {
                return nil
            }
            return sample.memoryPressure.map(WidgetReading.pressure) ?? .unavailable
        case .swapUsed:
            guard sample.read.contains(.swap) else {
                return nil
            }
            return sample.swap.map { WidgetReading.bytes($0.used) } ?? .unavailable
        default:
            guard sample.read.contains(.memory) else {
                return nil
            }
            guard let memory = sample.memory else {
                return .unavailable
            }
            if preset == .gigabytesUsed {
                return .bytes(memory.used)
            }
            return WidgetReadings.usedFraction(used: memory.used, total: memory.total).map(WidgetReading.fraction)
                ?? .unavailable
        }
    }

    private static func diskSpaceReading(_ space: DiskSpace?, preset: WidgetPreset) -> WidgetReading {
        guard let space else {
            return .unavailable
        }
        if preset == .gigabytesFree {
            return space.available >= 0 ? .bytes(UInt64(space.available)) : .unavailable
        }
        return WidgetReadings.diskFreeFraction(available: space.available, total: space.total).map(WidgetReading.fraction)
            ?? .unavailable
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
        texts.pressureNormal = String(localized: "Normal")
        texts.pressureHigh = String(localized: "High")
        texts.pressureCritical = String(localized: "Critical")
        cache[key] = texts
        return texts
    }
}
