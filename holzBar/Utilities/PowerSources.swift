//
//  PowerSources.swift
//  holzBar
//

import Foundation
import IOKit.ps
import OSLog

/// What an internal battery reported at one moment.
nonisolated struct BatterySnapshot: Equatable, Sendable {
    /// The level as a whole percentage, rounded down; `nil` when the battery reports no
    /// maximum capacity.
    var percent: Int?
    /// Whether the Mac runs on the battery.
    var isOnBattery: Bool
    var isCharging: Bool
    var isCharged: Bool

    /// The state for the symbol next to the percentage.
    var state: BatteryState {
        BatteryState(isOnBattery: isOnBattery, isCharging: isCharging, isCharged: isCharged)
    }
}

/// What the power sources of the Mac said.
nonisolated enum PowerSourceReading: Equatable, Sendable {
    /// IOKit gave no list of power sources.
    case unreadable
    /// The Mac has no internal battery and runs on its adapter.
    case noBattery
    case battery(BatterySnapshot)
}

/// The one reading of the internal battery, shared by the automation rules and the widgets
/// (D-03: one reading, not two). Only the numbers come from IOKit; the arithmetic is
/// ``BatteryLevel`` and ``BatteryState``.
nonisolated enum PowerSources {
    /// Reads the power sources once. It never blocks and reads nothing but the power source
    /// description.
    static func read() -> PowerSourceReading {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return .unreadable
        }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else {
                continue
            }
            var percent: Int?
            if let current = description[kIOPSCurrentCapacityKey] as? Int, let maximum = description[kIOPSMaxCapacityKey] as? Int {
                percent = BatteryLevel.percent(current: current, maximum: maximum)
            }
            return .battery(
                BatterySnapshot(
                    percent: percent,
                    isOnBattery: description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                    isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                    isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
                )
            )
        }
        return .noBattery
    }

    /// The internal battery, or `nil` on a Mac without one.
    static func internalBattery() -> BatterySnapshot? {
        if case .battery(let snapshot) = read() {
            return snapshot
        }
        return nil
    }
}

extension Notification.Name {
    /// Posted on the main thread when IOKit reports a change of a power source.
    nonisolated static let powerSourcesDidChange = Notification.Name("HolzBarPowerSourcesDidChange")
}

/// IOKit's callback is a C function that cannot capture anything, so it posts a notification.
nonisolated private func postPowerSourcesDidChange(_ context: UnsafeMutableRawPointer?) {
    NotificationCenter.default.post(name: .powerSourcesDidChange, object: nil)
}

/// The one IOKit run loop source for power source changes, shared by everything that follows
/// them. It exists on the main run loop only while something has asked for it with ``begin()``
/// and not yet given it back with ``end()``; with no user nothing observes anything.
@MainActor
final class PowerSourceEvents {
    static let shared = PowerSourceEvents()

    private let logger = Logger(category: "PowerSourceEvents")
    private var users = 0
    private var source: CFRunLoopSource?

    /// Asks for power source events: ``Foundation/Notification/Name/powerSourcesDidChange`` is
    /// posted for each change until the last user calls ``end()``.
    func begin() {
        users += 1
        guard source == nil else {
            return
        }
        if let created = IOPSNotificationCreateRunLoopSource(postPowerSourcesDidChange, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
            source = created
        } else {
            logger.error("Could not observe power source changes")
        }
    }

    /// Gives the events back. Every call pairs with one of ``begin()``.
    func end() {
        guard users > 0 else {
            return
        }
        users -= 1
        guard users == 0, let source else {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = nil
    }
}
