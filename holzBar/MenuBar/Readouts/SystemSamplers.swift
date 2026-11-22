//
//  SystemSamplers.swift
//  holzBar
//

import Darwin
import Foundation

/// Reads the numbers of the system readouts that come from the kernel and the file system.
///
/// Each function reads once and returns the value, or `nil` when the system did not answer;
/// none of them has a timer, a cache or a side effect, and none logs what it read (D-03, D-13).
/// The arithmetic behind the numbers (the load between two readings, the memory in use, the
/// shares) is in `WidgetReadings` and `ReadoutValues`, where it is tested. The battery is read by
/// ``PowerSources``. ``read(_:refreshesDiskSpace:)`` is the one entry of the shared monitor and
/// runs off the main actor (D-12).
nonisolated enum SystemSamplers {
    /// The host port. `mach_host_self()` adds a send right to the task on every call, so it is
    /// read once.
    private static let host: mach_port_t = mach_host_self()

    /// Reads the requested metrics once, off the main actor, and hands them back as plain values.
    ///
    /// The sample lists in ``ReadoutSample/read`` exactly the metrics this function filled, so a
    /// consumer can tell a metric that failed (listed, value `nil`) from one that was not asked
    /// for. The total CPU and the network counters are filled so far; the plans that add a metric
    /// add its reader here.
    ///
    /// - Parameters:
    ///   - metrics: What to read. A metric that has no reader yet is left out of the sample.
    ///   - refreshesDiskSpace: Whether the free disk space is read again, which is not cheap.
    @concurrent
    static func read(_ metrics: Set<ReadoutMetric>, refreshesDiskSpace: Bool) async -> ReadoutSample {
        var sample = ReadoutSample(at: ContinuousClock.now)
        if metrics.contains(.cpu) {
            sample.read.insert(.cpu)
            sample.cpuTicks = cpuTicks()
        }
        if metrics.contains(.network) {
            sample.read.insert(.network)
            sample.network = networkCounters(at: sample.at)
        }
        return sample
    }

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

    /// The most interface records of one table that are read; a table that is longer is cut, so a
    /// corrupt answer never makes a long loop.
    private static let maximumInterfaceRecords = 1_024

    /// The 64-bit byte counters of the interfaces that count as the Mac's network traffic
    /// (``NetworkInterfaceRule``), from the interface table of the routing sockets
    /// (`sysctl` with `NET_RT_IFLIST2`). No Wi-Fi API and no network call: the kernel keeps the
    /// counters. The names stay inside the sum and are never logged (D-10).
    ///
    /// - Returns: `nil` when the table could not be read or holds no interface that counts.
    static func networkCounters(at instant: ContinuousClock.Instant) -> CounterSnapshot? {
        guard let records = interfaceRecords() else {
            return nil
        }
        let counters = NetworkInterfaceRule.counters(records)
        guard !counters.isEmpty else {
            return nil
        }
        return CounterSnapshot(at: instant, counters: counters)
    }

    /// Every interface of the table, with its type, state and counters. The buffer is sized by a
    /// first call and read with unaligned loads; a record with a zero length, or one that runs past
    /// the end, stops the walk (T-94-07).
    private static func interfaceRecords() -> [InterfaceRecord]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        // The table may grow between the two calls, so the buffer has room to spare.
        var capacity = size + size / 4 + 1_024
        var buffer = [UInt8](repeating: 0, count: capacity)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &capacity, nil, 0) == 0, capacity > 0 else {
            return nil
        }
        let used = min(capacity, buffer.count)
        return buffer.withUnsafeBytes { raw in
            parseInterfaces(raw, used: used)
        }
    }

    private static func parseInterfaces(_ raw: UnsafeRawBufferPointer, used: Int) -> [InterfaceRecord] {
        var records = [InterfaceRecord]()
        var offset = 0
        var visited = 0
        // The first fields of every message: the length (two bytes), the version and the type.
        while offset + 4 <= used, visited < maximumInterfaceRecords {
            visited += 1
            let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            guard length > 0, offset + length <= used else {
                break
            }
            defer {
                offset += length
            }
            let messageType = raw.loadUnaligned(fromByteOffset: offset + 3, as: UInt8.self)
            guard messageType == UInt8(RTM_IFINFO2), length >= MemoryLayout<if_msghdr2>.size else {
                continue
            }
            let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
            let isUp = (header.ifm_flags & IFF_UP) != 0
            // Only an Ethernet type interface that is up can count; the name is looked up for
            // those alone.
            guard isUp, header.ifm_data.ifi_type == NetworkInterfaceRule.ethernetType,
                let name = interfaceName(Int(header.ifm_index)) else {
                continue
            }
            records.append(
                InterfaceRecord(
                    name: name,
                    type: header.ifm_data.ifi_type,
                    isUp: isUp,
                    inputBytes: header.ifm_data.ifi_ibytes,
                    outputBytes: header.ifm_data.ifi_obytes
                )
            )
        }
        return records
    }

    /// The name of the interface with the index, such as `en0`.
    private static func interfaceName(_ index: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
        guard let index = UInt32(exactly: index), if_indextoname(index, &buffer) != nil else {
            return nil
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
    }
}
