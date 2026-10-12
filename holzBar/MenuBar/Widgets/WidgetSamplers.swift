//
//  WidgetSamplers.swift
//  holzBar
//

import Darwin
import Foundation

/// Reads the numbers of the widget sources that come from the kernel and the file system.
///
/// Each function reads once and returns the value, or `nil` when the system did not answer;
/// none of them has a timer, a cache or a side effect, and none logs what it read (D-03, D-13).
/// The arithmetic behind the numbers (the load between two readings, the memory in use, the
/// shares) is in `WidgetReadings`, where it is tested. The battery is read by ``PowerSources``.
nonisolated enum WidgetSamplers {
    /// The host port. `mach_host_self()` adds a send right to the task on every call, so it is
    /// read once.
    private static let host: mach_port_t = mach_host_self()

    /// The tick counters of all processors, summed, from `host_statistics` with
    /// `HOST_CPU_LOAD_INFO`. The structure is on the stack, so nothing has to be freed.
    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { raw in
                host_statistics(host, HOST_CPU_LOAD_INFO, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        // The order of the counters is CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE and
        // CPU_STATE_NICE.
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// The memory in use, counted the way Activity Monitor counts it, and the installed memory,
    /// from `host_statistics64` with `HOST_VM_INFO64`.
    static func memory() -> (used: UInt64, total: UInt64)? {
        var statistics = vm_statistics64_data_t()
        // The count is computed from the size of the structure in `integer_t` units, because the
        // C macro `HOST_VM_INFO64_COUNT` is not imported.
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { raw in
                host_statistics64(host, HOST_VM_INFO64, raw, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return nil
        }
        let pages = MemoryPages(
            internalPages: UInt64(statistics.internal_page_count),
            purgeable: UInt64(statistics.purgeable_count),
            wired: UInt64(statistics.wire_count),
            compressed: UInt64(statistics.compressor_page_count)
        )
        return (pages.usedBytes(pageSize: UInt64(pageSize)), ProcessInfo.processInfo.physicalMemory)
    }

    /// The space available for important usage and the capacity of the startup volume.
    static func diskSpace() -> (available: Int64, total: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard
            let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
            let available = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity
        else {
            return nil
        }
        return (available, Int64(total))
    }

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
