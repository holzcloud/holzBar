//
//  WidgetSamplers.swift
//  holzBar
//

import Darwin
import Foundation

/// Reads the numbers of the widget sources that are not system readouts.
///
/// The readers of the CPU, the memory and the free disk space belong to the shared monitor and
/// are in ``SystemSamplers``. This reads once and returns the value, or `nil` when the system did
/// not answer; it has no timer, no cache and no side effect, and it logs nothing (D-03, D-13).
nonisolated enum WidgetSamplers {
    /// The moment the Mac booted, from `sysctlbyname("kern.boottime")`.
    static func bootDate() -> Date? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(boot.tv_sec) + TimeInterval(boot.tv_usec) / 1_000_000)
    }
}
