//
//  NowPlayingRemote.swift
//  holzBar
//
//  The helper of the Now Playing module's "Read all apps". It is the only file of holzBar
//  that names MediaRemote, an Apple framework whose interface is private: Apple documents none
//  of it, and no public call reads what another app plays. Since macOS 15.4 the framework
//  answers an ordinary app with nothing, but it still answers Apple's own platform binaries, so
//  holzBar never loads this file itself. It starts /usr/bin/perl, and perl loads this library
//  and calls nowplaying_get (once) or nowplaying_stream (until holzBar ends the process); the
//  access comes from perl's identity, not from this library. See CLAUDE.md, "Private API in
//  modules".
//
//  What protects the app: the library is signed with holzBar's certificate and no entitlement
//  and checked with the app before it starts; every private function is looked up when it is
//  first needed and a missing one ends the process with a named reason instead of a crash; it
//  prints one JSON object per line on standard output and nothing else (the title, artist,
//  album, length, position and the playing app's bundle identifier, no pictures and no file
//  paths); it opens no network connection, reads no file, starts no process, logs nothing and
//  polls nothing; and it ends when the process that started perl ends.
//
//  The protocol (version 1), one object per line:
//    {"v":1,"bundle":"com.apple.Safari","playing":true,"title":"…","artist":"…","album":"…",
//     "duration":215.0,"elapsed":12.3,"rate":1.0,"at":1730000000.5}   the app that plays
//    {"v":1,"none":true}                                              nothing plays
//    {"v":1,"error":"framework"}   also "symbol", "unavailable" and "timeout"; the process then
//                                  exits with 3, 4, 5 or 6
//

import Dispatch
import Foundation

// MARK: The private framework

/// The binary of the private framework, looked up at run time.
private let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
private typealias ClientFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
private typealias BundleFunction = @convention(c) (AnyObject?) -> Unmanaged<CFString>?
private typealias PlayingFunction = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void
private typealias RegisterFunction = @convention(c) (DispatchQueue) -> Void

/// The functions of the framework that the helper uses.
private struct MediaRemote: Sendable {
    let info: InfoFunction
    let client: ClientFunction
    let bundle: BundleFunction
    let playing: PlayingFunction
    let register: RegisterFunction?
}

/// Why the helper could not ask; the raw value is what the protocol prints.
private enum Failure: String, Error {
    case framework
    case symbol
    case unavailable
    case timeout

    var exitCode: Int32 {
        switch self {
        case .framework: 3
        case .symbol: 4
        case .unavailable: 5
        case .timeout: 6
        }
    }
}

/// Loads the framework and finds its functions. `register` is needed only to stream.
private func loadMediaRemote(needsRegister: Bool) -> Result<MediaRemote, Failure> {
    guard let handle = dlopen(frameworkPath, RTLD_LAZY) else {
        return .failure(.framework)
    }
    guard let info = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
          let client = dlsym(handle, "MRMediaRemoteGetNowPlayingClient"),
          let bundle = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier"),
          let playing = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") else {
        return .failure(.symbol)
    }
    let register = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications")
    if needsRegister, register == nil {
        return .failure(.symbol)
    }
    return .success(MediaRemote(
        info: unsafeBitCast(info, to: InfoFunction.self),
        client: unsafeBitCast(client, to: ClientFunction.self),
        bundle: unsafeBitCast(bundle, to: BundleFunction.self),
        playing: unsafeBitCast(playing, to: PlayingFunction.self),
        register: register.map { unsafeBitCast($0, to: RegisterFunction.self) }
    ))
}

// MARK: Output

/// Writes the text and a newline to standard output, all of it, or ends the process when the
/// reader has gone.
private func emit(_ text: String) {
    let bytes = Array((text + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
        let written = bytes[offset...].withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress, $0.count) }
        if written > 0 {
            offset += written
        } else if written < 0, errno == EINTR {
            continue
        } else {
            exit(0)
        }
    }
}

/// Prints the error object and ends the process with the failure's exit code.
private func fail(_ failure: Failure) -> Never {
    emit(#"{"v":1,"error":"\#(failure.rawValue)"}"#)
    exit(failure.exitCode)
}

// MARK: Reading

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

/// The keys of the protocol, read from the framework's dictionary.
private struct Info: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var rate: Double?
    /// When `elapsed` was true, in seconds since 1970.
    var timestamp: Double?

    var hasText: Bool {
        title != nil || artist != nil || album != nil
    }

    init(_ dictionary: CFDictionary?) {
        guard let values = dictionary as? [AnyHashable: Any] else {
            return
        }
        func text(_ key: String) -> String? {
            guard let string = values[key] as? String else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(500))
        }
        func number(_ key: String) -> Double? {
            guard let number = (values[key] as? NSNumber)?.doubleValue, number.isFinite else { return nil }
            return number
        }
        title = text("kMRMediaRemoteNowPlayingInfoTitle")
        artist = text("kMRMediaRemoteNowPlayingInfoArtist")
        album = text("kMRMediaRemoteNowPlayingInfoAlbum")
        duration = number("kMRMediaRemoteNowPlayingInfoDuration")
        elapsed = number("kMRMediaRemoteNowPlayingInfoElapsedTime")
        rate = number("kMRMediaRemoteNowPlayingInfoPlaybackRate")
        timestamp = (values["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)?.timeIntervalSince1970
    }
}

/// Asks the framework once for the app, whether it plays and the dictionary, and returns the
/// protocol line, or `nil` when no answer came within the time. The framework answers on a
/// queue of its own, so the waiting thread is never the one that answers.
private func snapshotLine(_ remote: MediaRemote, timeout: Double) -> String? {
    let queue = DispatchQueue.global(qos: .utility)
    let infoDelivery = Delivery<Info>()
    let playingDelivery = Delivery<Bool>()
    let bundleDelivery = Delivery<String?>()
    remote.info(queue) { infoDelivery.deliver(Info($0)) }
    remote.playing(queue) { playingDelivery.deliver($0) }
    let bundle = remote.bundle
    remote.client(queue) { client in
        bundleDelivery.deliver(bundle(client)?.takeUnretainedValue() as String?)
    }
    guard let info = infoDelivery.wait(seconds: timeout),
          let isPlaying = playingDelivery.wait(seconds: timeout),
          let appIdentifier = bundleDelivery.wait(seconds: timeout) else {
        return nil
    }
    // Without a bundle identifier the app cannot be named, so nothing is reported.
    guard let appIdentifier, !appIdentifier.isEmpty, isPlaying || info.hasText else {
        return #"{"v":1,"none":true}"#
    }
    var object: [String: Any] = ["v": 1, "bundle": appIdentifier, "playing": isPlaying]
    object["title"] = info.title
    object["artist"] = info.artist
    object["album"] = info.album
    object["duration"] = info.duration
    object["elapsed"] = info.elapsed
    object["rate"] = info.rate
    object["at"] = info.timestamp
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        return #"{"v":1,"none":true}"#
    }
    return text
}

// MARK: Ending with the parent

/// Ends the process when the process that started it ends, or at once when that is already
/// gone. The returned source must stay alive for as long as the process runs.
private func endWithParent(on queue: DispatchQueue) -> DispatchSourceProcess {
    let parent = getppid()
    if parent <= 1 || kill(parent, 0) != 0 {
        exit(0)
    }
    let source = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: queue)
    source.setEventHandler { exit(0) }
    source.resume()
    return source
}

// MARK: Streaming

/// Runs an action 150 ms after the last request, so a burst of notifications asks once.
private final class Debouncer: @unchecked Sendable {
    private let queue: DispatchQueue
    private let action: @Sendable () -> Void
    private var pending: DispatchWorkItem?

    init(queue: DispatchQueue, action: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.action = action
    }

    func request() {
        queue.async {
            self.pending?.cancel()
            let item = DispatchWorkItem(block: self.action)
            self.pending = item
            self.queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
        }
    }
}

/// The notifications the framework posts once registered for them.
private let notificationNames = [
    "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
]

// MARK: Entry points for perl

/// Prints the current state once and returns.
@_cdecl("nowplaying_get")
public func nowplayingGet() {
    switch loadMediaRemote(needsRegister: false) {
    case .failure(let failure):
        fail(failure)
    case .success(let remote):
        guard let line = snapshotLine(remote, timeout: 3) else {
            fail(.timeout)
        }
        emit(line)
    }
}

/// Prints the current state at once, then a line after every change, and never returns: the
/// process ends when its parent ends.
@_cdecl("nowplaying_stream")
public func nowplayingStream() {
    let remote: MediaRemote
    switch loadMediaRemote(needsRegister: true) {
    case .failure(let failure):
        fail(failure)
    case .success(let loaded):
        remote = loaded
    }
    let queue = DispatchQueue(label: "ch.holzcloud.holzBar.NowPlayingRemote")
    let parent = endWithParent(on: queue)
    let report: @Sendable () -> Void = {
        guard let line = snapshotLine(remote, timeout: 3) else {
            fail(.timeout)
        }
        emit(line)
    }
    let debouncer = Debouncer(queue: queue, action: report)
    queue.async(execute: report)
    remote.register?(DispatchQueue.global(qos: .utility))
    let observers = notificationNames.map { name in
        NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: nil) { _ in
            debouncer.request()
        }
    }
    withExtendedLifetime((parent, observers)) {
        dispatchMain()
    }
}
