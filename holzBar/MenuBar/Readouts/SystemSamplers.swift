//
//  SystemSamplers.swift
//  holzBar
//

import Darwin
import Foundation
import IOKit
import IOKit.ps

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
    /// for. The total CPU, the memory, the swap, the memory pressure level, the free disk space, the
    /// network counters and the disk counters are filled so far; the plans that add a metric add its
    /// reader here.
    ///
    /// - Parameters:
    ///   - metrics: What to read. A metric that has no reader yet is left out of the sample.
    ///   - refreshesDiskSpace: Whether the precise free disk space (the figure Finder shows) is read;
    ///     otherwise only the cheap `statfs` figure is.
    @concurrent
    static func read(_ metrics: Set<ReadoutMetric>, refreshesDiskSpace: Bool) async -> ReadoutSample {
        var sample = ReadoutSample(at: ContinuousClock.now)
        if metrics.contains(.cpu) {
            sample.read.insert(.cpu)
            sample.cpuTicks = cpuTicks()
        }
        if metrics.contains(.cpuCores) {
            // The sum of the cores is the total, so a consumer of the cores needs no other read.
            sample.read.insert(.cpuCores)
            sample.cpuCoreTicks = cpuCoreTicks()
        }
        if metrics.contains(.memory) {
            sample.read.insert(.memory)
            sample.memory = memory()
        }
        if metrics.contains(.swap) {
            sample.read.insert(.swap)
            sample.swap = swapUsage()
        }
        if metrics.contains(.memoryPressure) {
            // The level at the time of the first reading; later changes come from the monitor's
            // event source, never from a timer (D-10).
            sample.read.insert(.memoryPressure)
            sample.memoryPressure = memoryPressureLevel()
        }
        if metrics.contains(.power) {
            // The values at the time of the first reading; later changes come from the monitor's
            // power source event, never from a timer (D-10).
            sample.read.insert(.power)
            sample.power = powerReading()
        }
        if metrics.contains(.thermal) {
            sample.read.insert(.thermal)
            sample.thermal = thermalState()
        }
        if metrics.contains(.diskSpace) {
            sample.read.insert(.diskSpace)
            sample.diskSpace = diskSpace(precise: refreshesDiskSpace)
        }
        if metrics.contains(.network) {
            sample.read.insert(.network)
            sample.network = networkCounters(at: sample.at)
        }
        if metrics.contains(.diskActivity) {
            sample.read.insert(.diskActivity)
            sample.disk = diskCounters(at: sample.at)
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

    /// The tick counters of every processor, one entry per core in the order of
    /// `host_processor_info` (the slowest cores first, see ``CPUClusters``).
    ///
    /// The call hands back an array the kernel allocated in this task; it is released with
    /// `vm_deallocate` in `defer`, with the size the kernel gave, on every path (T-94-25).
    ///
    /// - Returns: `nil` when the call failed or answered with no core.
    static func cpuCoreTicks() -> [CPUTicks]? {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else {
            return nil
        }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }
        let states = Int(CPU_STATE_MAX)
        let cores = Int(processorCount)
        // The array holds `CPU_STATE_MAX` counters for each core; a shorter one is not used.
        guard cores > 0, Int(infoCount) >= cores * states else {
            return nil
        }
        func counter(_ core: Int, _ state: Int32) -> UInt64 {
            UInt64(UInt32(bitPattern: info[core * states + Int(state)]))
        }
        return (0..<cores).map { core in
            CPUTicks(
                user: counter(core, CPU_STATE_USER),
                system: counter(core, CPU_STATE_SYSTEM),
                idle: counter(core, CPU_STATE_IDLE),
                nice: counter(core, CPU_STATE_NICE)
            )
        }
    }

    /// The most performance levels read; a chip that claims more is read as one without clusters.
    private static let maximumClusterLevels = 8

    /// The performance levels of this Mac as the kernel lists them, fastest first, read once: the
    /// count, the logical processors and the name of every level. Empty on a Mac that reports no
    /// level (Intel), and when any value of a level is missing, so the cluster format shows the
    /// total (D-10, D-11). The names are kept in memory only.
    static let clusterLevels: [ClusterLevel] = {
        guard let count = sysctlInteger("hw.nperflevels"), (1...maximumClusterLevels).contains(count) else {
            return []
        }
        var levels = [ClusterLevel]()
        for index in 0..<count {
            guard let cpus = sysctlInteger("hw.perflevel\(index).logicalcpu"), cpus > 0 else {
                return []
            }
            let name = sysctlText("hw.perflevel\(index).name") ?? ""
            levels.append(ClusterLevel(index: index, name: name, logicalCPUs: cpus))
        }
        return levels
    }()

    /// A 32-bit integer sysctl value, or `nil` when the name is unknown.
    private static func sysctlInteger(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, size == MemoryLayout<Int32>.size else {
            return nil
        }
        return Int(value)
    }

    /// A string sysctl value, or `nil` when the name is unknown. A value longer than 64 bytes is
    /// not a level name and is left out.
    private static func sysctlText(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0, size <= 64 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
    }

    /// The memory in use, counted the way Activity Monitor counts it, and the installed memory,
    /// from `host_statistics64` with `HOST_VM_INFO64`.
    static func memory() -> MemoryUse? {
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
        return MemoryUse(used: pages.usedBytes(pageSize: UInt64(pageSize)), total: ProcessInfo.processInfo.physicalMemory)
    }

    /// The swap in use and its total, from the swap usage sysctl.
    static func swapUsage() -> SwapUsage? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0, size == MemoryLayout<xsw_usage>.size else {
            return nil
        }
        return SwapUsage(total: usage.xsu_total, used: usage.xsu_used)
    }

    /// The memory pressure level the kernel reports now, from
    /// `sysctl kern.memorystatus_vm_pressure_level`.
    static func memoryPressureLevel() -> ReadoutPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        return ReadoutPressure(kernelLevel: Int(level))
    }

    /// The thermal state the system reports now, from `ProcessInfo`. A later change comes from the
    /// monitor's thermal notification (D-10).
    static func thermalState() -> ReadoutThermal? {
        ReadoutThermal(rawState: ProcessInfo.processInfo.thermalState.rawValue)
    }

    /// The internal battery as one power reading, or `nil` on a Mac without one or when it gives
    /// no level.
    ///
    /// The percent and the state come from ``PowerSources`` (Current Capacity against Max
    /// Capacity, so a charge limit is respected, D-10). The minutes until empty and until full
    /// come from the battery's power source description and the adapter's watts from the system's
    /// description of the external adapter; each goes through ``PowerValues``, so a sentinel
    /// ("calculating", "unknown"), a negative or an impossible value is `nil` and never a number
    /// (D-11, T-94-14).
    static func powerReading() -> PowerReading? {
        guard let battery = PowerSources.internalBattery(), let percent = battery.percent else {
            return nil
        }
        let minutes = batteryMinutes()
        var adapter: Int?
        if
            !battery.isOnBattery,
            let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        {
            adapter = details[kIOPSPowerAdapterWattsKey] as? Int
        }
        return PowerReading(
            percent: percent,
            state: battery.state,
            timeToEmpty: PowerValues.duration(minutes: minutes.toEmpty),
            timeToFull: PowerValues.duration(minutes: minutes.toFull),
            adapterWatts: PowerValues.watts(adapter)
        )
    }

    /// The minutes the internal battery gives until empty and until full, as the system wrote
    /// them (not yet checked).
    private static func batteryMinutes() -> (toEmpty: Int?, toFull: Int?) {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return (nil, nil)
        }
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else {
                continue
            }
            return (description[kIOPSTimeToEmptyKey] as? Int, description[kIOPSTimeToFullChargeKey] as? Int)
        }
        return (nil, nil)
    }

    /// The free space and the capacity of the startup volume.
    ///
    /// The cheap figure is `statfs`, about a microsecond. The precise one is the space available
    /// for important usage, which counts what the system may free and is the figure Finder shows;
    /// it is asked of the system only when `precise` is true. When the precise figure cannot be
    /// read, the cheap one stands in for it.
    ///
    /// - Returns: `nil` when neither could be read.
    static func diskSpace(precise: Bool) -> DiskSpace? {
        var statistics = statfs()
        var cheap: (available: Int64, total: Int64)?
        if statfs("/", &statistics) == 0 {
            let blockSize = Int64(statistics.f_bsize)
            let available = Int64(clamping: statistics.f_bavail).multipliedReportingOverflow(by: blockSize)
            let total = Int64(clamping: statistics.f_blocks).multipliedReportingOverflow(by: blockSize)
            if !available.overflow, !total.overflow {
                cheap = (available.partialValue, total.partialValue)
            }
        }
        if precise {
            let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
            if
                let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
                let available = values.volumeAvailableCapacityForImportantUsage,
                let total = values.volumeTotalCapacity
            {
                return DiskSpace(available: available, total: Int64(total), quickAvailable: cheap?.available)
            }
        }
        guard let cheap else {
            return nil
        }
        return DiskSpace(available: cheap.available, total: cheap.total, quickAvailable: cheap.available)
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

    /// The bytes read and written since boot by each block storage driver, as one snapshot keyed
    /// by the driver's registry entry ID, so a disk that is removed vanishes from the sum and
    /// never makes a negative rate (``RateBaseline`` leaves out a counter only one snapshot has).
    /// Every iterator and entry is released in `defer`; the copied property is taken with
    /// `takeRetainedValue()` (T-94-08).
    ///
    /// - Returns: `nil` when the registry could not be read or holds no driver with statistics.
    static func diskCounters(at instant: ContinuousClock.Instant) -> CounterSnapshot? {
        var iterator = io_iterator_t()
        guard
            IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS
        else {
            return nil
        }
        defer {
            IOObjectRelease(iterator)
        }
        var counters = [String: CounterPair]()
        while counters.count < maximumInterfaceRecords {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else {
                break
            }
            defer {
                IOObjectRelease(entry)
            }
            var identifier: UInt64 = 0
            guard
                IORegistryEntryGetRegistryEntryID(entry, &identifier) == KERN_SUCCESS,
                let property = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0),
                let statistics = property.takeRetainedValue() as? [String: Any]
            else {
                continue
            }
            var bytes = [String: Int64]()
            for key in [DiskStatistics.readKey, DiskStatistics.writeKey] {
                if let number = statistics[key] as? NSNumber {
                    bytes[key] = number.int64Value
                }
            }
            if let pair = DiskStatistics.counters(bytes) {
                counters[String(identifier)] = pair
            }
        }
        guard !counters.isEmpty else {
            return nil
        }
        return CounterSnapshot(at: instant, counters: counters)
    }
}
