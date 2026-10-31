//
//  RemoteProbe.swift
//  now-playing
//
//  A throwaway spike that ships nothing, and the only file of the package that names the
//  private MediaRemote framework. The interface is private: Apple documents none of it, and
//  from macOS 15.4 on it answers an ordinary app with nothing, while it still answers a
//  platform process such as /usr/bin/perl. This probe asks it once, read-only, to record on a
//  real Mac whether it answers when called from the probe's own process (the "direct" route) and
//  when perl loads this code as a dynamic library (the "perl" route): the evidence for the
//  maintainer's decision D-08 of Phase 38. holzBar.app never links or loads this library or the
//  private framework. Only the count and the names of the dictionary's keys leave this file,
//  never a value, and the library opens no network connection and writes no file.
//

import Dispatch
import Foundation

/// The file name of the private framework's binary (private API, looked up at run time).
private let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
private typealias ClientFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
private typealias BundleFunction = @convention(c) (AnyObject?) -> Unmanaged<CFString>?

/// Holds what a callback delivers, for the thread that waits.
private final class Delivery<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: Value?
    private var delivered = false

    func deliver(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        guard !delivered else { return }
        delivered = true
        value = newValue
        semaphore.signal()
    }

    /// The delivered value, or nil when nothing arrived within the time.
    func wait(seconds: Double) -> Value? {
        guard semaphore.wait(timeout: .now() + seconds) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// The key names of a dictionary, or nil when the dictionary is nil.
private struct InfoKeys: Sendable {
    let names: [String]
}

private func architecture() -> String {
    #if _ptrauth(_arm64e)
    return "arm64e"
    #elseif arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "-"
    #endif
}

/// The line `REMOTEPROBE arch=<> loaded=<y|n> symbols=<> result=<> app=<> keys=<>`.
public func remoteProbeReport() -> String {
    let arch = architecture()
    func line(loaded: Bool, symbols: String, result: String, app: String?, keys: [String]) -> String {
        let names = keys.isEmpty ? "-" : keys.prefix(40).joined(separator: ";")
        return "REMOTEPROBE arch=\(arch) loaded=\(loaded ? "y" : "n") symbols=\(symbols) result=\(result) app=\(app ?? "-") keys=\(names)"
    }

    guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
        return line(loaded: false, symbols: "-", result: "loadfail", app: nil, keys: [])
    }
    func symbol(_ name: String) -> UnsafeMutableRawPointer? { dlsym(handle, name) }
    let info = symbol("MRMediaRemoteGetNowPlayingInfo")
    let client = symbol("MRMediaRemoteGetNowPlayingClient")
    let bundle = symbol("MRNowPlayingClientGetBundleIdentifier")
    let playing = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying")
    let notify = symbol("MRMediaRemoteRegisterForNowPlayingNotifications")
    func flag(_ pointer: UnsafeMutableRawPointer?) -> String { pointer == nil ? "n" : "y" }
    let symbols = "info:\(flag(info));client:\(flag(client));bundle:\(flag(bundle));playing:\(flag(playing));notify:\(flag(notify))"

    guard let info else {
        return line(loaded: true, symbols: symbols, result: "symbolfail", app: nil, keys: [])
    }

    // Once, on a global queue, waiting at most three seconds.
    let queue = DispatchQueue.global(qos: .utility)
    let infoDelivery = Delivery<InfoKeys>()
    unsafeBitCast(info, to: InfoFunction.self)(queue) { dictionary in
        let names = ((dictionary as? [AnyHashable: Any]) ?? [:]).keys.map { String(describing: $0) }
        infoDelivery.deliver(InfoKeys(names: names.sorted()))
    }
    guard let delivered = infoDelivery.wait(seconds: 3) else {
        return line(loaded: true, symbols: symbols, result: "timeout", app: nil, keys: [])
    }

    var app: String?
    if let client, let bundle {
        let clientDelivery = Delivery<String?>()
        let bundleFunction = unsafeBitCast(bundle, to: BundleFunction.self)
        unsafeBitCast(client, to: ClientFunction.self)(queue) { clientObject in
            clientDelivery.deliver(bundleFunction(clientObject)?.takeUnretainedValue() as String?)
        }
        app = clientDelivery.wait(seconds: 3) ?? nil
    }

    let result = delivered.names.isEmpty ? "empty" : "keys:\(delivered.names.count)"
    return line(loaded: true, symbols: symbols, result: result, app: app, keys: delivered.names)
}

/// Exported so that perl can call it: prints the report to standard output and flushes it.
@_cdecl("nowplaying_probe_get")
public func nowplayingProbeGet() {
    FileHandle.standardOutput.write(Data((remoteProbeReport() + "\n").utf8))
}
