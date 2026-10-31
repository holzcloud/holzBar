//
//  AccessoryTracker.swift
//  holzBar
//

import Foundation

/// A change in the set of connected accessories.
nonisolated enum AccessoryEvent: Equatable, Sendable {
    case connected(AccessoryDevice)
    case disconnected(AccessoryDevice)
}

/// Turns snapshots of the connected accessories into connect and disconnect events, as a pure
/// value that reads no clock.
///
/// The first update is a baseline and returns no event: the devices that were already connected
/// when holzBar started are not news. Every later update compares its snapshot with the one
/// before, by device id (a renamed device is the same device, and a device listed twice counts
/// once). Disconnects come before connects, each ordered by name and then id, and a disconnect
/// carries the device as it was in the previous snapshot.
///
/// An event is dropped when the same kind of event for the same device was reported less than
/// ``quietPeriod`` seconds before, so AirPods in and out of their case raise one alert. The two
/// kinds of event do not suppress each other, and a dropped event is not counted as reported.
/// The tracker holds device names, so it lives in memory only and its owner resets it when it
/// stops.
nonisolated struct AccessoryTracker: Equatable, Sendable {
    /// How long a repeated event of one kind for one device is ignored, in seconds.
    static let quietPeriod: TimeInterval = 10

    private var previous: [String: AccessoryDevice]?
    private var lastConnected = [String: Date]()
    private var lastDisconnected = [String: Date]()

    init() {}

    /// Compares the devices connected now with the previous snapshot and returns the events,
    /// except for the first call, which only records the baseline.
    mutating func update(connected devices: [AccessoryDevice], now: Date) -> [AccessoryEvent] {
        var current = [String: AccessoryDevice]()
        for device in devices where current[device.id] == nil {
            current[device.id] = device
        }
        defer {
            previous = current
        }
        guard let previous else {
            return []
        }
        var events = [AccessoryEvent]()
        let gone = previous.values.filter { current[$0.id] == nil }
        for device in Self.ordered(gone) where Self.isFresh(lastDisconnected[device.id], now: now) {
            lastDisconnected[device.id] = now
            events.append(.disconnected(device))
        }
        let arrived = current.values.filter { previous[$0.id] == nil }
        for device in Self.ordered(arrived) where Self.isFresh(lastConnected[device.id], now: now) {
            lastConnected[device.id] = now
            events.append(.connected(device))
        }
        lastConnected = Self.pruned(lastConnected, now: now)
        lastDisconnected = Self.pruned(lastDisconnected, now: now)
        return events
    }

    /// Forgets the snapshot and the dates, so the next update is a baseline again.
    mutating func reset() {
        previous = nil
        lastConnected.removeAll()
        lastDisconnected.removeAll()
    }

    /// Whether an event is allowed: none was reported before, or the last one is at least the
    /// quiet period old, or lies in the future (a clock that went back).
    private static func isFresh(_ last: Date?, now: Date) -> Bool {
        guard let last else {
            return true
        }
        let age = now.timeIntervalSince(last)
        return age < 0 || age >= quietPeriod
    }

    private static func ordered(_ devices: [AccessoryDevice]) -> [AccessoryDevice] {
        devices.sorted { left, right in
            let leftName = left.name.lowercased()
            let rightName = right.name.lowercased()
            if leftName != rightName {
                return leftName < rightName
            }
            if left.name != right.name {
                return left.name < right.name
            }
            return left.id < right.id
        }
    }

    /// Drops the dates that can no longer suppress anything.
    private static func pruned(_ dates: [String: Date], now: Date) -> [String: Date] {
        dates.filter { now.timeIntervalSince($0.value) < quietPeriod }
    }
}
