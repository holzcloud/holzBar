//
//  LocalChecks.swift
//  now-playing
//

import AppKit
import AVFoundation
import Darwin
import Foundation
import ImageIO
import NowPlayingProbeCore

/// The media keys, as the system-defined events of `IOKit/hidsystem/ev_keymap.h` carry them.
enum MediaKeyCode {
    /// NX_KEYTYPE_PLAY, NX_KEYTYPE_NEXT and NX_KEYTYPE_PREVIOUS.
    static let playPause = 16
    static let next = 17
    static let previous = 18

    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS.
    static let subtype: Int16 = 8

    /// The state bits of the event: 0xa00 for a key going down, 0xb00 for going up.
    static func stateBits(isDown: Bool) -> Int { isDown ? 0xa00 : 0xb00 }

    /// `data1` of the event: the key code in the high half, the state bits in the low half.
    static func data1(code: Int, isDown: Bool) -> Int {
        (code << 16) | stateBits(isDown: isDown)
    }

    static func code(named name: String) -> Int? {
        switch name {
        case "play": playPause
        case "next": next
        case "previous": previous
        default: nil
        }
    }
}

/// `keys`, `artwork` and `access`: the small checks that need one action each. None of them
/// prints a title, a file name or picture data; the probe writes no file.
@MainActor
enum LocalChecks {
    // MARK: - keys

    static func validateKeys(_ options: Options) -> Problem? {
        guard options.positional.count == 1, MediaKeyCode.code(named: options.positional[0]) != nil else {
            return Problem(message: "keys needs play, next or previous")
        }
        return nil
    }

    static func runKeys(session: Session) {
        let name = session.options.positional[0]
        guard let code = MediaKeyCode.code(named: name) else { return }
        session.step("Make sure the app you want to test is playing. One \(name) key is posted in 3 seconds.")
        session.step("This needs Accessibility for the terminal (System Settings, Privacy and Security).")
        for remaining in stride(from: 3, through: 1, by: -1) {
            session.step("\(remaining)")
            Thread.sleep(forTimeInterval: 1)
        }
        let allowed = CGPreflightPostEventAccess()
        if allowed {
            post(code: code, isDown: true)
            post(code: code, isDown: false)
        } else {
            session.step("macOS refuses to post events: give the terminal Accessibility and run the step again.")
        }
        Output.emit("KEYS", [("key", name), ("posted", allowed ? "y" : "n")])

        var toggled: Bool?
        var app: String?
        if allowed {
            toggled = session.ask("Did the playback change (it started, paused or skipped)?")
            if toggled != nil { app = session.askChoice("Which app reacted?", choices: ["music", "spotify", "other"]) }
        }
        // One run tests one app, so the verdict of this run covers that app only.
        let controls: Verdict.Result? = toggled.map { value in
            Verdict.controls(
                musicToggled: app == "music" ? value : nil,
                spotifyToggled: app == "spotify" ? value : nil
            )
        }
        Output.emit(Verdict.summaryLine(
            music: nil, spotify: nil, others: 0, source: nil, controls: controls, remote: nil
        ))
        session.answer(keyToggled: toggled.map { $0 ? "y" : "n" }, keyApp: app)
        session.end()
    }

    private static func post(code: Int, isDown: Bool) {
        let bits = MediaKeyCode.stateBits(isDown: isDown)
        let event = NSEvent.otherEvent(
            with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(bits)),
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: MediaKeyCode.subtype,
            data1: MediaKeyCode.data1(code: code, isDown: isDown), data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - artwork

    static func validateArtwork(_ options: Options) -> Problem? {
        options.positional.count == 1 ? nil : Problem(message: "artwork needs the path of one song")
    }

    /// Reads the embedded picture of one local song and writes one ARTWORK line.
    static func runArtwork(session: Session) {
        let path = session.options.positional[0]
        session.step("Reading the embedded picture of one song. No file name and no picture data are printed.")
        let result = ArtworkResult.read(path: path)
        Output.emit("ARTWORK", [
            ("present", result.present.map { $0 ? "y" : "n" }),
            ("bytes", result.bytes.map(String.init)),
            ("width", result.width.map(String.init)),
            ("height", result.height.map(String.init)),
        ])
        Output.emit(Verdict.summaryLine(
            music: nil, spotify: nil, others: 0, source: nil, controls: nil, remote: nil
        ))
        session.answer()
        session.end()
    }

    // MARK: - access

    /// Lists `~/Music` and `~/Music/Music` and writes one ACCESS line each: whether macOS lets
    /// an app list the music folder without a prompt. No name is read from the listing.
    static func runAccess(session: Session) {
        session.step("Listing the music folder, which tells whether macOS asks for it. Nothing is printed from the listing.")
        for path in ["~/Music", "~/Music/Music"] {
            let expanded = NSString(string: path).expandingTildeInPath
            Output.emit("ACCESS", [("path", path), ("listing", listing(of: expanded))])
        }
        Output.emit(Verdict.summaryLine(
            music: nil, spotify: nil, others: 0, source: nil, controls: nil, remote: nil
        ))
        session.answer()
        session.end()
    }

    /// `ok`, or `denied:<errno>` (1 is the refusal of a protected folder, 2 a missing one).
    static func listing(of path: String) -> String {
        guard let directory = opendir(path) else { return "denied:\(errno)" }
        defer { closedir(directory) }
        errno = 0
        _ = readdir(directory)
        return errno == 0 ? "ok" : "denied:\(errno)"
    }

    // MARK: - selftest

    /// The pure parts: the key codes and the event data formula, against literals.
    static func selftestMismatches() -> [String] {
        var mismatches: [String] = []
        func check(_ name: String, _ actual: Int, _ expected: Int) {
            if actual != expected { mismatches.append("\(name): got \(actual) expected \(expected)") }
        }
        check("play code", MediaKeyCode.code(named: "play") ?? -1, 16)
        check("next code", MediaKeyCode.code(named: "next") ?? -1, 17)
        check("previous code", MediaKeyCode.code(named: "previous") ?? -1, 18)
        check("play down", MediaKeyCode.data1(code: 16, isDown: true), 0x10_0a00)
        check("play up", MediaKeyCode.data1(code: 16, isDown: false), 0x10_0b00)
        check("next down", MediaKeyCode.data1(code: 17, isDown: true), 0x11_0a00)
        check("previous up", MediaKeyCode.data1(code: 18, isDown: false), 0x12_0b00)
        check("subtype", Int(MediaKeyCode.subtype), 8)
        return mismatches
    }
}

/// What the embedded picture of a song is: present or not, its size in bytes and pixels.
struct ArtworkResult: Sendable {
    var present: Bool?
    var bytes: Int?
    var width: Int?
    var height: Int?

    private final class Box: @unchecked Sendable {
        var result = ArtworkResult()
    }

    /// Blocks the calling thread until the asset has been read (at most 20 seconds).
    static func read(path: String) -> ArtworkResult {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.result = await load(path: path)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 20)
        return box.result
    }

    private static func load(path: String) async -> ArtworkResult {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let metadata = try? await asset.load(.commonMetadata) else { return ArtworkResult() }
        let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        guard let item = items.first else { return ArtworkResult(present: false) }
        guard let data = try? await item.load(.dataValue) else { return ArtworkResult(present: false) }
        var result = ArtworkResult(present: true, bytes: data.count)
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            result.width = properties[kCGImagePropertyPixelWidth] as? Int
            result.height = properties[kCGImagePropertyPixelHeight] as? Int
        }
        return result
    }
}
