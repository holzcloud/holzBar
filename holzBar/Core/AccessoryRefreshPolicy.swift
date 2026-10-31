//
//  AccessoryRefreshPolicy.swift
//  holzBar
//

import Foundation

/// When the accessory batteries are read again without an event.
///
/// The coarse wait exists because no documented event reports an accessory's level changing
/// (45-CONTEXT F6). It can go if the Mac check shows that the power-source notification fires
/// for accessories.
nonisolated enum AccessoryRefreshPolicy {
    /// The wait between two reads, in seconds.
    static let interval: TimeInterval = 300

    /// The moment of the next read, or `nil` when nothing needs one.
    ///
    /// - Parameters:
    ///   - hasBatteryAccessory: Whether a connected accessory reported a level in the last read.
    ///   - lastRead: When that read happened.
    static func next(hasBatteryAccessory: Bool, lastRead: Date) -> Date? {
        hasBatteryAccessory ? lastRead.addingTimeInterval(interval) : nil
    }
}
