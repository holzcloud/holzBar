// Answers four questions about the battery levels of accessories (keyboards, mice, AirPods)
// that holzBar's Accessory alerts module reads (phase 45, plan 45-02, spike P-05 and P-06):
//
//   S-1  Does `dlsym` on the default handle find the one undocumented IOKit function that
//        lists accessory power sources?
//   S-2  How many accessory sources does it return, and how many of them carry a name, a
//        current capacity and a maximum capacity?
//   S-3  For each source (numbered): its category, its percentage, its low-warning level and
//        whether its identifier has the shape of a UUID.
//   S-4  (only with --listen) Does the public power-source notification fire when an
//        accessory connects, leaves or changes its level?
//
// This is a measuring aid and not part of the app. It only reads: it never calls IOBluetooth
// or CoreBluetooth, never opens a connection, never starts a process and never writes a file.
// It prints no device name unless started with `--names`; an accessory's name can be the
// owner's own name, so paste the output of a default run only.
//
// Build and run (the Command Line Tools are enough):
//
//   swiftc Scripts/accessories/accessory-battery-probe.swift -o "$TMPDIR/holzbar-accessory-probe"
//   "$TMPDIR/holzbar-accessory-probe"                   S-1 to S-3, then exit
//   "$TMPDIR/holzbar-accessory-probe" --listen 60       also S-4 for 60 seconds: connect or
//                                                       disconnect an accessory meanwhile
//   "$TMPDIR/holzbar-accessory-probe" --names           also print the names (S-3)
//
// (It also compiles with `-swift-version 6`.)
//
// The undocumented function is looked up by name at run time, exactly as the app does. The
// type value 4 selects accessory sources (measured on macOS 26.7.1, 45-CONTEXT F4).
import Foundation
import IOKit.ps

// Lines reach a pipe or a file as they are printed, not when the buffer fills.
setvbuf(stdout, nil, _IOLBF, 0)

enum Probe {
    /// The name of the undocumented function, looked up with `dlsym`.
    static let symbolName = "IOPSCopyPowerSourcesByType"
    /// The type value that selects accessory sources.
    static let accessorySourcesType: Int32 = 4
}

typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

/// The function found by `dlsym`, or nil.
func lookUp() -> CopyPowerSourcesByType? {
    // RTLD_DEFAULT, which Swift does not import.
    let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
    guard let symbol = dlsym(defaultHandle, Probe.symbolName) else {
        return nil
    }
    return unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)
}

/// Every accessory description the call returns now, or an empty list.
func readAccessories() -> [[String: Any]] {
    guard
        let function = lookUp(),
        let info = function(Probe.accessorySourcesType)?.takeRetainedValue(),
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else {
        return []
    }
    return sources.compactMap { source in
        IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
    }
}

func number(_ value: Any?) -> Int? {
    // A Bool is also an NSNumber; it never counts as a capacity.
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else {
        return nil
    }
    return value.intValue
}

func percent(_ description: [String: Any]) -> Int? {
    guard
        let current = number(description["Current Capacity"]),
        let maximum = number(description["Max Capacity"]),
        maximum > 0,
        current >= 0
    else {
        return nil
    }
    return min(100, current * 100 / maximum)
}

func isUUIDShaped(_ value: Any?) -> Bool {
    guard let text = value as? String else {
        return false
    }
    return UUID(uuidString: text) != nil
}

let arguments = CommandLine.arguments
let showsNames = arguments.contains("--names")
var listenSeconds = 0.0
if let index = arguments.firstIndex(of: "--listen"), index + 1 < arguments.count {
    listenSeconds = Double(arguments[index + 1]) ?? 0
}

let version = ProcessInfo.processInfo.operatingSystemVersionString
print("macOS \(version)")

// S-1
let found = lookUp() != nil
print("S-1 symbol \(Probe.symbolName) found by dlsym: \(found ? "yes" : "no")")

// S-2
let descriptions = readAccessories()
let complete = descriptions.filter { description in
    let name = description["Name"] as? String ?? ""
    return !name.isEmpty && percent(description) != nil
}
print("S-2 accessory sources: \(descriptions.count), with name and both capacities: \(complete.count)")

// S-3
for (index, description) in descriptions.enumerated() {
    let category = description["Accessory Category"] as? String ?? "n/a"
    let level = percent(description).map { "\($0)%" } ?? "n/a"
    let warning = number(description["Low Warn Level"]).map { "\($0)" } ?? "n/a"
    let uuid = isUUIDShaped(description["Accessory Identifier"]) ? "yes" : "no"
    var line = "S-3 #\(index + 1) category=\(category) percent=\(level) lowWarn=\(warning) identifierIsUUID=\(uuid)"
    if showsNames {
        line += " name=\(description["Name"] as? String ?? "n/a")"
    }
    print(line)
}

// S-4
let started = Date()

/// The callback of the public notification. A C callback captures nothing, so it reads again.
func powerSourcesChanged(_ context: UnsafeMutableRawPointer?) {
    let now = readAccessories()
    let lowest = now.compactMap(percent).min().map { "\($0)%" } ?? "n/a"
    let seconds = Int(Date().timeIntervalSince(started))
    print("S-4 t=\(seconds)s notification: accessory sources=\(now.count) lowest=\(lowest)")
}

if listenSeconds > 0 {
    if let source = IOPSNotificationCreateRunLoopSource(powerSourcesChanged, nil)?.takeRetainedValue() {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        print("S-4 listening for \(Int(listenSeconds)) seconds")
        CFRunLoopRunInMode(.defaultMode, listenSeconds, false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        print("S-4 done")
    } else {
        print("S-4 could not create the power source notification")
    }
} else {
    print("S-4 not run (use --listen <seconds>)")
}
