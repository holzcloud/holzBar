//
//  AccessoryBatterySource.swift
//  holzBar
//

import Foundation
import IOKit.ps
import OSLog

/// Reads the battery levels of accessories (AirPods, keyboards, mice) from the accessory power
/// sources.
///
/// **This file is the only place in holzBar that uses the undocumented call
/// `IOPSCopyPowerSourcesByType`.** It is used because no public API gives an accessory's level:
/// the documented power-source calls return the Mac's own battery only, and reading a level
/// over Bluetooth would mean connecting to the user's devices (45-CONTEXT F1 to F5). It is
/// permitted by the exception clause "Private API only by exception, per module" in `CLAUDE.md`
/// and sits behind the setting "Read battery levels", which Settings describes as an
/// undocumented call. It sends nothing anywhere and logs nothing about the accessories, at most
/// how many there are.
///
/// The symbol is looked up with `dlsym` at run time and never linked at build time, so a macOS
/// that drops it cannot stop holzBar from launching: ``isAvailable`` is false and ``read()``
/// returns an empty list. What it returns goes through ``AccessoryBatteryReading``, which
/// trusts nothing in it. No Bluetooth framework is used here.
nonisolated enum AccessoryBatterySource {
    /// The type value of the undocumented call that selects accessory sources (the Mac's own
    /// battery is another value). Measured in 45-CONTEXT F4.
    static let accessorySources: Int32 = 4

    private typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    private static let logger = Logger(category: "AccessoryBatterySource")

    /// The function, found once on the default handle, or `nil` when this macOS has no such
    /// symbol.
    private static let copyPowerSources: CopyPowerSourcesByType? = {
        // RTLD_DEFAULT, which Swift does not import.
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(defaultHandle, "IOPSCopyPowerSourcesByType") else {
            logger.notice("The accessory battery call is not available on this macOS")
            return nil
        }
        return unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)
    }()

    /// Whether this macOS offers the call.
    static var isAvailable: Bool {
        copyPowerSources != nil
    }

    /// The batteries of the accessories that report one now, or an empty list when the call is
    /// missing or returns nothing.
    ///
    /// The caller checks the "Read battery levels" setting before calling; this function never
    /// reads it. It runs off the main actor.
    @concurrent
    static func read() async -> [AccessoryBattery] {
        guard
            let copyPowerSources,
            let info = copyPowerSources(accessorySources)?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return []
        }
        let descriptions = sources.compactMap { source in
            IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        }
        let batteries = AccessoryBatteryReading.batteries(from: descriptions)
        logger.debug("Read \(batteries.count, privacy: .public) accessory batteries")
        return batteries
    }
}
