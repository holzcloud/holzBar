import Foundation
import Testing
@testable import HolzBarCore

@Suite("ReadoutValues")
struct ReadoutValuesTests {
    private let start = ContinuousClock.now

    private func snapshot(
        _ seconds: Int,
        _ counters: [String: CounterPair]
    ) -> CounterSnapshot {
        CounterSnapshot(at: start + .seconds(seconds), counters: counters)
    }

    private func pair(_ first: UInt64, _ second: UInt64) -> CounterPair {
        CounterPair(first: first, second: second)
    }

    private func record(
        _ name: String,
        type: UInt8 = 6,
        isUp: Bool = true,
        input: UInt64 = 0,
        output: UInt64 = 0
    ) -> InterfaceRecord {
        InterfaceRecord(name: name, type: type, isUp: isUp, inputBytes: input, outputBytes: output)
    }

    // MARK: RateBaseline

    @Test("The first snapshot is only a baseline")
    func firstSnapshotIsABaseline() {
        var baseline = RateBaseline()
        #expect(baseline.rates(snapshot(0, ["en0": pair(100, 100)])) == nil)
    }

    @Test("Two snapshots give the rate per second")
    func twoSnapshotsGiveARate() {
        var baseline = RateBaseline()
        _ = baseline.rates(snapshot(0, ["en0": pair(1_000, 5_000)]))
        let rates = baseline.rates(snapshot(2, ["en0": pair(3_000, 9_000)]))
        #expect(rates == ReadoutRates(first: 1_000, second: 2_000))

        // The newest snapshot is the next baseline.
        let next = baseline.rates(snapshot(3, ["en0": pair(3_500, 9_000)]))
        #expect(next == ReadoutRates(first: 500, second: 0))
    }

    @Test("Counters add up over the interfaces both snapshots have")
    func interfacesAdd() {
        var baseline = RateBaseline()
        _ = baseline.rates(snapshot(0, ["en0": pair(0, 0), "en1": pair(0, 0)]))
        let rates = baseline.rates(snapshot(1, ["en0": pair(100, 10), "en1": pair(50, 5)]))
        #expect(rates == ReadoutRates(first: 150, second: 15))
    }

    @Test("An interface that came or went is left out and never makes a negative rate")
    func vanishedInterface() {
        var baseline = RateBaseline()
        _ = baseline.rates(snapshot(0, ["en0": pair(0, 0), "en5": pair(1_000_000, 1_000_000)]))
        // en5 is gone, en7 is new.
        let rates = baseline.rates(snapshot(2, ["en0": pair(2_000, 4_000), "en7": pair(9_000_000, 9_000_000)]))
        #expect(rates == ReadoutRates(first: 1_000, second: 2_000))
    }

    @Test("A counter that went backwards is left out and its new value is the baseline")
    func backwardsCounter() {
        var baseline = RateBaseline()
        _ = baseline.rates(snapshot(0, ["en0": pair(1_000, 1_000), "en1": pair(0, 0)]))
        let first = baseline.rates(snapshot(1, ["en0": pair(10, 10), "en1": pair(100, 100)]))
        #expect(first == ReadoutRates(first: 100, second: 100))

        // Only the backwards interface: nothing honest to say.
        var single = RateBaseline()
        _ = single.rates(snapshot(0, ["en0": pair(1_000, 1_000)]))
        #expect(single.rates(snapshot(1, ["en0": pair(10, 10)])) == nil)
        // The next interval counts from the new value.
        #expect(single.rates(snapshot(2, ["en0": pair(60, 110)])) == ReadoutRates(first: 50, second: 100))
    }

    @Test("A counter that wraps is left out, never a huge rate")
    func wrappedCounter() {
        var baseline = RateBaseline()
        _ = baseline.rates(snapshot(0, ["en0": pair(UInt64.max - 10, UInt64.max - 10)]))
        #expect(baseline.rates(snapshot(1, ["en0": pair(5, 5)])) == nil)
    }

    @Test("No interface in common, no time between and a failed read give nothing")
    func nothingToSay() {
        var disjoint = RateBaseline()
        _ = disjoint.rates(snapshot(0, ["en0": pair(0, 0)]))
        #expect(disjoint.rates(snapshot(1, ["en1": pair(10, 10)])) == nil)

        var instant = RateBaseline()
        _ = instant.rates(snapshot(5, ["en0": pair(0, 0)]))
        #expect(instant.rates(snapshot(5, ["en0": pair(10, 10)])) == nil)

        var failed = RateBaseline()
        _ = failed.rates(snapshot(0, ["en0": pair(0, 0)]))
        #expect(failed.rates(nil) == nil)
        // The baseline is gone: the next snapshot is a baseline again.
        #expect(failed.rates(snapshot(1, ["en0": pair(10, 10)])) == nil)
        #expect(failed.rates(snapshot(2, ["en0": pair(30, 30)])) == ReadoutRates(first: 20, second: 20))
    }

    @Test("A gap over 300 seconds gives nothing and rebases")
    func longGap() {
        var baseline = RateBaseline()
        _ = baseline.rates(snapshot(0, ["en0": pair(0, 0)]))
        #expect(baseline.rates(snapshot(301, ["en0": pair(1_000_000, 1_000_000)])) == nil)
        #expect(baseline.rates(snapshot(302, ["en0": pair(1_000_100, 1_000_200)])) == ReadoutRates(first: 100, second: 200))

        var edge = RateBaseline()
        _ = edge.rates(snapshot(0, ["en0": pair(0, 0)]))
        #expect(edge.rates(snapshot(300, ["en0": pair(3_000, 6_000)])) == ReadoutRates(first: 10, second: 20))
        #expect(RateBaseline.maximumGap == .seconds(300))
    }

    // MARK: NetworkInterfaceRule

    @Test("Only en plus digits of Ethernet type that are up count")
    func interfaceRule() {
        #expect(NetworkInterfaceRule.counts(record("en0")))
        #expect(NetworkInterfaceRule.counts(record("en12")))
        #expect(!NetworkInterfaceRule.counts(record("en0", isUp: false)))
        #expect(!NetworkInterfaceRule.counts(record("en5", type: 1)))
        for name in ["en", "ena", "en0x", "anpi0", "awdl0", "llw0", "ap1", "utun0", "bridge0", "lo0", "gif0", "stf0", "nan0", "EN0"] {
            #expect(!NetworkInterfaceRule.counts(record(name)), "\(name) must not count")
        }
        // Digits are ASCII only.
        #expect(!NetworkInterfaceRule.counts(record("en\u{0663}")))
    }

    @Test("The counters keep only counted interfaces and add records of one name")
    func interfaceCounters() {
        let records = [
            record("en0", input: 100, output: 10),
            record("utun0", input: 999, output: 999),
            record("lo0", type: 24, input: 5, output: 5),
            record("en0", input: 50, output: 5),
            record("en1", isUp: false, input: 7, output: 7),
            record("en2", input: UInt64.max, output: 1),
            record("en2", input: 5, output: 1),
        ]
        let counters = NetworkInterfaceRule.counters(records)
        #expect(Set(counters.keys) == ["en0", "en2"])
        #expect(counters["en0"] == pair(150, 15))
        #expect(counters["en2"] == pair(UInt64.max, 2))
    }

    // MARK: DiskStatistics

    @Test("The disk statistics need both keys and no negative value")
    func diskStatistics() {
        #expect(DiskStatistics.counters(["Bytes (Read)": 10, "Bytes (Write)": 20, "Operations (Read)": 3]) == pair(10, 20))
        #expect(DiskStatistics.counters(["Bytes (Read)": 10]) == nil)
        #expect(DiskStatistics.counters(["Bytes (Write)": 10]) == nil)
        #expect(DiskStatistics.counters(["Bytes (Read)": -1, "Bytes (Write)": 20]) == nil)
        #expect(DiskStatistics.counters(["Bytes (Read)": 1, "Bytes (Write)": -20]) == nil)
        #expect(DiskStatistics.counters([:]) == nil)
    }

    @Test("A disk image or another virtual device is not a real disk, so its reads are not counted twice")
    func diskDriverRule() {
        #expect(DiskDriverRule.counts(deviceClass: "AppleANS3NVMeController", physicalInterconnect: "Apple Fabric"))
        #expect(DiskDriverRule.counts(deviceClass: "IOBlockStorageDevice", physicalInterconnect: "USB"))
        #expect(DiskDriverRule.counts(deviceClass: nil, physicalInterconnect: nil))
        #expect(!DiskDriverRule.counts(deviceClass: "IOBlockStorageDevice", physicalInterconnect: "Virtual Interface"))
        #expect(!DiskDriverRule.counts(deviceClass: "AppleDiskImageDevice", physicalInterconnect: nil))
        #expect(!DiskDriverRule.counts(deviceClass: "IOHDIXHDDriveOutKernel", physicalInterconnect: "Disk Image"))
    }

    @Test("Between two precise reads the kept free space is shown; a tick that read shows its own")
    func diskSpaceCache() {
        let kept = DiskSpace(available: 10, total: 100, quickAvailable: 10)
        let fresh = DiskSpace(available: 20, total: 100, quickAvailable: 19)
        #expect(DiskSpaceCache.figure(read: nil, kept: kept, refreshed: false) == kept)
        #expect(DiskSpaceCache.figure(read: fresh, kept: kept, refreshed: true) == fresh)
        // A failed read of a refreshing tick is missing, never an old figure.
        #expect(DiskSpaceCache.figure(read: nil, kept: kept, refreshed: true) == nil)
        // Nothing kept: whatever the tick read stands in.
        #expect(DiskSpaceCache.figure(read: fresh, kept: nil, refreshed: false) == fresh)
        #expect(DiskSpaceCache.figure(read: nil, kept: nil, refreshed: false) == nil)
    }

    // MARK: Power and GPU

    @Test("Battery minutes are believed only when they are possible")
    func powerDuration() {
        #expect(PowerValues.duration(minutes: nil) == nil)
        #expect(PowerValues.duration(minutes: -1) == nil)
        #expect(PowerValues.duration(minutes: 0) == nil)
        #expect(PowerValues.duration(minutes: 65_535) == nil)
        #expect(PowerValues.duration(minutes: 6_001) == nil)
        #expect(PowerValues.duration(minutes: 6_000) == .seconds(360_000))
        #expect(PowerValues.duration(minutes: 130) == .seconds(7_800))
    }

    @Test("The adapter's watts are never zero")
    func powerWatts() {
        #expect(PowerValues.watts(nil) == nil)
        #expect(PowerValues.watts(0) == nil)
        #expect(PowerValues.watts(-5) == nil)
        #expect(PowerValues.watts(96) == 96)
        #expect(PowerValues.watts(1_000) == 1_000)
        #expect(PowerValues.watts(1_001) == nil)
    }

    @Test("The graphics load stays inside 0 to 100")
    func gpuPercent() {
        #expect(GPUValues.percent(0) == 0)
        #expect(GPUValues.percent(100) == 100)
        #expect(GPUValues.percent(-1) == nil)
        #expect(GPUValues.percent(101) == nil)
        #expect(GPUValues.percent(nil) == nil)
    }

    // MARK: Pressure and thermal

    @Test("Memory pressure from an event mask and from the kernel level")
    func pressure() {
        #expect(ReadoutPressure(eventMask: 1) == .normal)
        #expect(ReadoutPressure(eventMask: 2) == .warning)
        #expect(ReadoutPressure(eventMask: 4) == .critical)
        #expect(ReadoutPressure(eventMask: 6) == .critical)
        #expect(ReadoutPressure(eventMask: 3) == .warning)
        #expect(ReadoutPressure(eventMask: 0) == nil)
        #expect(ReadoutPressure(kernelLevel: 1) == .normal)
        #expect(ReadoutPressure(kernelLevel: 2) == .warning)
        #expect(ReadoutPressure(kernelLevel: 4) == .critical)
        #expect(ReadoutPressure(kernelLevel: 0) == nil)
        #expect(ReadoutPressure(kernelLevel: 3) == nil)
        #expect(ReadoutPressure(kernelLevel: 8) == nil)
        #expect(ReadoutPressure.normal < .critical)
    }

    @Test("The thermal state from its raw value")
    func thermal() {
        #expect(ReadoutThermal(rawState: 0) == .nominal)
        #expect(ReadoutThermal(rawState: 1) == .fair)
        #expect(ReadoutThermal(rawState: 2) == .serious)
        #expect(ReadoutThermal(rawState: 3) == .critical)
        #expect(ReadoutThermal(rawState: 4) == nil)
        #expect(ReadoutThermal(rawState: -1) == nil)
        #expect(ReadoutThermal.fair < .serious)
    }

    // MARK: Sample and baseline

    @Test("Merging keeps the older fields the newer sample did not read")
    func merging() {
        var older = ReadoutSample(at: start)
        older.read = [.cpu, .memory, .thermal]
        older.cpuTicks = CPUTicks(user: 1, system: 1, idle: 1, nice: 0)
        older.memory = MemoryUse(used: 10, total: 100)
        older.thermal = .fair

        var newer = ReadoutSample(at: start + .seconds(5))
        newer.read = [.memory, .thermal]
        newer.memory = MemoryUse(used: 20, total: 100)
        newer.thermal = nil

        let merged = older.merging(newer)
        #expect(merged.at == start + .seconds(5))
        #expect(merged.read == [.cpu, .memory, .thermal])
        #expect(merged.cpuTicks == older.cpuTicks)
        #expect(merged.memory == MemoryUse(used: 20, total: 100))
        // A metric the newer sample read and could not get is missing, not the old value.
        #expect(merged.thermal == nil)
    }

    private func battery(_ name: String, _ percent: Int) -> AccessoryBattery {
        AccessoryBattery(id: "name:\(name)", name: name, percent: percent, lowWarnLevel: nil, category: nil)
    }

    @Test("The device batteries merge like the other fields")
    func mergingDeviceBatteries() {
        var older = ReadoutSample(at: start)
        older.read = [.deviceBattery]
        older.deviceBatteries = [battery("Mouse", 40)]

        // A newer sample that read them replaces them.
        var read = ReadoutSample(at: start + .seconds(5))
        read.read = [.deviceBattery]
        read.deviceBatteries = [battery("Keyboard", 80)]
        #expect(older.merging(read).deviceBatteries == [battery("Keyboard", 80)])

        // A newer sample that did not read them keeps the older value.
        var other = ReadoutSample(at: start + .seconds(5))
        other.read = [.cpu]
        #expect(older.merging(other).deviceBatteries == [battery("Mouse", 40)])

        // A newer sample that read them and got nothing sets nil, not the old value.
        var missing = ReadoutSample(at: start + .seconds(5))
        missing.read = [.deviceBattery]
        #expect(older.merging(missing).deviceBatteries == nil)
    }

    @Test("Every metric of a sample merges its own field")
    func mergingCoversEveryMetric() {
        var newer = ReadoutSample(at: start)
        newer.read = Set(ReadoutMetric.allCases)
        newer.cpuTicks = CPUTicks(user: 1, system: 0, idle: 0, nice: 0)
        newer.cpuCoreTicks = [CPUTicks(user: 1, system: 0, idle: 0, nice: 0)]
        newer.memory = MemoryUse(used: 1, total: 2)
        newer.swap = SwapUsage(total: 2, used: 1)
        newer.memoryPressure = .warning
        newer.network = snapshot(0, ["en0": pair(1, 1)])
        newer.disk = snapshot(0, ["disk": pair(1, 1)])
        newer.diskSpace = DiskSpace(available: 1, total: 2, quickAvailable: nil)
        newer.power = PowerReading(percent: 50, state: .onBattery, timeToEmpty: nil, timeToFull: nil, adapterWatts: nil)
        newer.thermal = .serious
        newer.gpuPercent = 12
        newer.deviceBatteries = [battery("Magic Keyboard", 80)]
        let merged = ReadoutSample(at: start).merging(newer)
        #expect(merged == newer)
    }

    @Test("The CPU load needs two readings and a reset starts again")
    func baselineCPULoad() {
        var baseline = ReadoutBaseline()
        let first = CPUTicks(user: 100, system: 100, idle: 800, nice: 0)
        let second = CPUTicks(user: 150, system: 150, idle: 900, nice: 0)
        #expect(baseline.cpuLoad(first) == nil)
        #expect(baseline.cpuLoad(second) == 0.5)

        baseline.reset()
        #expect(baseline.cpuLoad(second) == nil)
        // A failed read drops the baseline.
        #expect(baseline.cpuLoad(nil) == nil)
        #expect(baseline.cpuLoad(first) == nil)
    }

    @Test("The core ticks give a pair once an earlier list exists")
    func baselineCoreTicks() {
        var baseline = ReadoutBaseline()
        let first = [CPUTicks(user: 1, system: 1, idle: 1, nice: 0)]
        let second = [CPUTicks(user: 2, system: 2, idle: 2, nice: 0)]
        #expect(baseline.coreTicks(first) == nil)
        let pair = baseline.coreTicks(second)
        #expect(pair?.previous == first)
        #expect(pair?.current == second)
        #expect(baseline.coreTicks(nil) == nil)
        #expect(baseline.coreTicks(first) == nil)
    }

    @Test("The network and disk baselines are separate and reset with the rest")
    func baselineRates() {
        var baseline = ReadoutBaseline()
        #expect(baseline.networkRates(snapshot(0, ["en0": pair(0, 0)])) == nil)
        #expect(baseline.diskRates(snapshot(0, ["disk": pair(0, 0)])) == nil)
        #expect(baseline.networkRates(snapshot(1, ["en0": pair(10, 20)])) == ReadoutRates(first: 10, second: 20))
        #expect(baseline.diskRates(snapshot(2, ["disk": pair(100, 200)])) == ReadoutRates(first: 50, second: 100))
        baseline.reset()
        #expect(baseline.networkRates(snapshot(3, ["en0": pair(10, 20)])) == nil)
    }
}
