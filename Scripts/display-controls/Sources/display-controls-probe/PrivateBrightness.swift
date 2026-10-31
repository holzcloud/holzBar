//
//  PrivateBrightness.swift
//  display-controls
//
//  The one file of the probe that names the private display framework and its symbols.
//  This is private API: Apple does not document it and may change it with any macOS update.
//  It is here as a measurement for decision Q-01 only, in a throwaway probe that ships
//  nowhere; holzBar.app never loads it in this plan. The framework is loaded with `dlopen`
//  on first use, never linked, and a call is made only after all three symbols resolved.
//  The prototypes are assumptions taken from the tools that use this interface; the probe
//  records what it sees, and a result that contradicts them is a finding.
//

import Foundation
import Dispatch
import DisplayProbeCore

enum PrivateBrightness {
    typealias CanChangeFunction = @convention(c) (UInt32) -> Bool
    typealias GetFunction = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetFunction = @convention(c) (UInt32, Float) -> Int32

    /// The result of loading the framework and resolving its symbols.
    struct Symbols: Sendable {
        var loaded = false
        var resolved = 0
        var canChange: CanChangeFunction?
        var get: GetFunction?
        var set: SetFunction?

        /// Every call needs all three symbols.
        var usable: Bool { loaded && resolved == 3 }
    }

    /// The seconds after which a call that has not returned ends the run.
    static let blockedAfterSeconds = 2.0

    /// Loaded once, on first use.
    static let symbols: Symbols = {
        var result = Symbols()
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            return result
        }
        result.loaded = true
        if let pointer = dlsym(handle, "DisplayServicesCanChangeBrightness") {
            result.canChange = unsafeBitCast(pointer, to: CanChangeFunction.self)
            result.resolved += 1
        }
        if let pointer = dlsym(handle, "DisplayServicesGetBrightness") {
            result.get = unsafeBitCast(pointer, to: GetFunction.self)
            result.resolved += 1
        }
        if let pointer = dlsym(handle, "DisplayServicesSetBrightness") {
            result.set = unsafeBitCast(pointer, to: SetFunction.self)
            result.resolved += 1
        }
        return result
    }()

    /// Loads the framework and says whether it loaded and how many of the three symbols resolved.
    static func load() -> (loaded: Bool, symbols: Int) {
        (symbols.loaded, symbols.resolved)
    }

    // MARK: Timed calls

    /// Runs one private call with a watchdog: a call that has not returned after two seconds
    /// ends the run with a BLOCKED line instead of hanging. Returns the value and the
    /// milliseconds the call took.
    private static func timed<Value>(_ name: String, _ id: UInt32, _ body: () -> Value) -> (value: Value, ms: Double) {
        let watchdog = DispatchWorkItem {
            Out.emit("BLOCKED call=\(name) id=\(id) seconds=\(Int(blockedAfterSeconds))")
            Out.emit("STEP a private call did not return; the run ends here")
            Out.emit(Report.endLine)
            exit(5)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + blockedAfterSeconds, execute: watchdog)
        let start = DispatchTime.now().uptimeNanoseconds
        let value = body()
        let end = DispatchTime.now().uptimeNanoseconds
        watchdog.cancel()
        return (value, Double(end - start) / 1_000_000)
    }

    /// `CanChange` for a display; nil when the symbols are not all available.
    static func canChange(_ id: UInt32) -> (value: Bool, ms: Double)? {
        let table = symbols
        guard table.usable, let function = table.canChange else {
            return nil
        }
        let result = timed("CanChange", id) { function(id) }
        return (result.value, result.ms)
    }

    /// One read: the status the call returned and the value when the status is 0.
    struct Reading: Sendable {
        var status: Int32
        var value: Double?
        var ms: Double

        /// What the BRIGHTNESS line shows: the value, or the error status.
        var text: String {
            if let value { return Report.level(value) }
            return "err\(status)"
        }
    }

    /// `Get` for a display; nil when the symbols are not all available.
    static func get(_ id: UInt32) -> Reading? {
        let table = symbols
        guard table.usable, let function = table.get else {
            return nil
        }
        var level: Float = -1
        let result = timed("Get", id) { function(id, &level) }
        let value = result.value == 0 && level.isFinite ? Double(level) : nil
        return Reading(status: result.value, value: value, ms: result.ms)
    }

    /// `Set` for a display; returns the status. Called only from the guarded change paths.
    static func set(_ id: UInt32, _ value: Double) -> (status: Int32, ms: Double)? {
        let table = symbols
        guard table.usable, let function = table.set else {
            return nil
        }
        let result = timed("Set", id) { function(id, Float(value)) }
        return (result.value, result.ms)
    }

    // MARK: Measurement

    /// Everything the probe learned about one display.
    struct Measurement: Sendable {
        var id: UInt32
        var canChange: Bool?
        var reading: Reading?
        var changeTested = false
        var setStatus: Int32?
        var readBack: Double?
        var restored: Double?
        var target: Double?
        var slowestMs = 0.0
    }

    /// Reads a display: `CanChange` first, `Get` only when it is true. The change test runs
    /// only when `allowChange` is given and `Get` returned a value; it never runs otherwise.
    static func measure(_ id: UInt32, allowChange: Bool) -> Measurement {
        var measurement = Measurement(id: id)
        guard let can = canChange(id) else {
            return measurement
        }
        measurement.canChange = can.value
        measurement.slowestMs = can.ms
        guard can.value, let reading = get(id) else {
            return measurement
        }
        measurement.reading = reading
        measurement.slowestMs = max(measurement.slowestMs, reading.ms)
        guard allowChange, let original = reading.value else {
            return measurement
        }
        changeTest(id, original: original, into: &measurement)
        return measurement
    }

    /// Moves the level by 0.05, reads it back after 300 ms, puts the original back and reads
    /// it again. The original is registered first so an interrupt puts it back too.
    private static func changeTest(_ id: UInt32, original: Double, into measurement: inout Measurement) {
        let target = Verdict.target(from: original)
        measurement.changeTested = true
        measurement.target = target
        Restore.shared.remember(id, original: original)
        defer { Restore.shared.forget(id) }

        guard let setCall = set(id, target) else {
            return
        }
        measurement.setStatus = setCall.status
        measurement.slowestMs = max(measurement.slowestMs, setCall.ms)
        Thread.sleep(forTimeInterval: 0.3)
        if let read = get(id) {
            measurement.readBack = read.value
            measurement.slowestMs = max(measurement.slowestMs, read.ms)
        }
        if let back = set(id, original) {
            measurement.slowestMs = max(measurement.slowestMs, back.ms)
        }
        Thread.sleep(forTimeInterval: 0.3)
        if let read = get(id) {
            measurement.restored = read.value
            measurement.slowestMs = max(measurement.slowestMs, read.ms)
        }
    }

    /// `brightness --set <value> --allow-change`: sets one value by hand and reads it back.
    static func setOnce(_ id: UInt32, value: Double) -> Measurement {
        var measurement = Measurement(id: id)
        guard let can = canChange(id) else {
            return measurement
        }
        measurement.canChange = can.value
        guard can.value, let setCall = set(id, value) else {
            return measurement
        }
        measurement.setStatus = setCall.status
        measurement.target = value
        Thread.sleep(forTimeInterval: 0.3)
        if let read = get(id) {
            measurement.reading = read
            measurement.readBack = read.value
        }
        return measurement
    }

    // MARK: Restoring on interrupt

    /// Remembers what a running change test must put back, so SIGINT and SIGTERM restore it
    /// before the probe exits. Other parts of the probe (the volume change test) register
    /// a closure here too.
    final class Restore: @unchecked Sendable {
        static let shared = Restore()

        private let lock = NSLock()
        private var brightness: [UInt32: Double] = [:]
        private var actions: [String: @Sendable () -> Void] = [:]
        private var sources: [DispatchSourceSignal] = []

        func remember(_ id: UInt32, original: Double) {
            lock.lock()
            brightness[id] = original
            lock.unlock()
        }

        func forget(_ id: UInt32) {
            lock.lock()
            brightness[id] = nil
            lock.unlock()
        }

        func remember(action name: String, _ action: @escaping @Sendable () -> Void) {
            lock.lock()
            actions[name] = action
            lock.unlock()
        }

        func forget(action name: String) {
            lock.lock()
            actions[name] = nil
            lock.unlock()
        }

        /// Puts back everything that is registered.
        func restoreAll() {
            lock.lock()
            let levels = brightness
            let pending = Array(actions.values)
            lock.unlock()
            for (id, original) in levels {
                _ = PrivateBrightness.set(id, original)
            }
            for action in pending {
                action()
            }
        }

        /// Interrupt (SIGINT) and terminate (SIGTERM) restore what a change test moved,
        /// write the end of the report and exit.
        func installSignalHandlers() {
            for number in [SIGINT, SIGTERM] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
                source.setEventHandler {
                    self.restoreAll()
                    Out.emit("STEP interrupted; what a change test moved was put back")
                    Out.emit(Report.endLine)
                    exit(128 + number)
                }
                source.resume()
                lock.lock()
                sources.append(source)
                lock.unlock()
            }
        }
    }
}
