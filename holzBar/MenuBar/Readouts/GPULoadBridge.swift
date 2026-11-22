//
//  GPULoadBridge.swift
//  holzBar
//

import Foundation
import IOKit

/// The one file of the app that names the graphics driver's undocumented utilization statistic.
///
/// This is the single wrapper of the named exception "System readouts, Read GPU load" under
/// "Private API in modules" in `CLAUDE.md` (decision of 2026-11-21). macOS has no public API for
/// how busy the graphics processor is. The driver publishes a statistics dictionary on its
/// accelerator services in the I/O registry, and one number in it is the load in percent; the
/// dictionary and the number are not documented and a macOS update can change or remove them.
/// What protects the app:
/// - The registry is read with public IOKit calls only (no `dlopen`, no `dlsym`, no private
///   framework): the accelerator services are matched, and each one's statistics are copied.
/// - Nothing here runs while the module's Read GPU load switch is off, because the only caller,
///   ``SystemMonitor``, never reaches this file then; and it reads only while a GPU tile is open.
/// - A missing service or number is an answer, not a crash: ``probe()`` turns it into the start
///   check of ``PrivateFeatureGate``, and ``read()`` into a failure the monitor counts, so the
///   part switches itself off for the session.
/// - Every registry object is released with `IOObjectRelease` in `defer`, on every path.
///
/// The file keeps no observer, starts no timer, logs nothing and never uses the network. The
/// number stays in memory.
nonisolated enum GPULoadBridge {
    /// What one read of the graphics load gave.
    enum Reading: Equatable, Sendable {
        /// The load of the busiest graphics processor, a whole percent from 0 to 100.
        case percent(Int)
        /// An accelerator answered, but not with the number: the interface changed.
        case keyMissing
        /// There is no accelerator, or the registry did not answer, or the number was impossible.
        case failed
    }

    /// What the registry holds, before it is turned into a reading.
    private enum Scan {
        case noAccelerator
        case missing
        case impossible
        case percent(Int)
    }

    /// The name of the statistics dictionary of an accelerator service.
    private static let statisticsKey = "PerformanceStatistics"
    /// The entry of that dictionary that holds the load in percent.
    private static let utilizationKey = "Device Utilization %"
    /// The class name of the graphics driver's accelerator services.
    private static let acceleratorClass = "IOAccelerator"

    /// Reads the load of the busiest graphics processor once, off the main actor.
    @concurrent
    static func read() async -> Reading {
        switch scan() {
        case .percent(let value): .percent(value)
        case .missing: .keyMissing
        case .noAccelerator, .impossible: .failed
        }
    }

    /// The start check: whether this Mac has an accelerator and whether it publishes the number.
    /// It reads once and keeps nothing.
    @concurrent
    static func probe() async -> PrivateFeatureGate.LoadResult {
        switch scan() {
        case .percent: .loaded
        case .noAccelerator: .frameworkMissing
        case .missing, .impossible: .symbolMissing
        }
    }

    /// Walks the accelerator services and takes the highest load: a Mac with two graphics
    /// processors reports the busier one.
    private static func scan() -> Scan {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(acceleratorClass), &iterator)
                == KERN_SUCCESS
        else {
            return .noAccelerator
        }
        defer { IOObjectRelease(iterator) }
        var sawService = false
        var sawNumber = false
        var highest: Int?
        var sawImpossible = false
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else {
                break
            }
            defer { IOObjectRelease(entry) }
            sawService = true
            guard let value = utilization(of: entry) else {
                continue
            }
            sawNumber = true
            guard let percent = GPUValues.percent(value) else {
                sawImpossible = true
                continue
            }
            highest = max(highest ?? percent, percent)
        }
        if let highest {
            return .percent(highest)
        }
        if !sawService {
            return .noAccelerator
        }
        return sawNumber && sawImpossible ? .impossible : .missing
    }

    /// The load in the statistics of one accelerator service, or `nil` when it has none.
    private static func utilization(of entry: io_registry_entry_t) -> Int? {
        guard
            let statistics = IORegistryEntryCreateCFProperty(
                entry, statisticsKey as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
            let number = statistics[utilizationKey] as? NSNumber
        else {
            return nil
        }
        return number.intValue
    }
}
