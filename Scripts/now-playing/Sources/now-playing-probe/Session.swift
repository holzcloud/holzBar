//
//  Session.swift
//  now-playing
//

import Darwin
import Foundation
import NowPlayingProbeCore
import Security

/// Standard output only; the probe writes no file.
enum Output {
    static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func emit(_ tag: String, _ pairs: [(String, String?)]) {
        emit(ReportLine.format(tag: tag, pairs))
    }
}

/// What the maintainer says plays during a `mediaremote` run (`--playing`).
enum Playing: String {
    case music, spotify, browser, video, other, none
}

struct Problem: Error {
    let message: String
}

struct Options {
    var command = ""
    var positional: [String] = []
    var label: String?
    var seconds = 180
    var showValues = false
    var playing = Playing.none

    static let usage = """
    usage: now-playing-probe notify [--label L] [--seconds N] [--redact | --show-values]
           now-playing-probe mediaremote direct | perl DYLIB [--playing music|spotify|browser|video|other|none]
           now-playing-probe keys play|next|previous
           now-playing-probe artwork PATH
           now-playing-probe access
           now-playing-probe selftest
    """

    static func parse(_ arguments: [String]) -> Result<Options, Problem> {
        var options = Options()
        var index = 0
        func value(for flag: String) -> Result<String, Problem> {
            index += 1
            guard index < arguments.count else { return .failure(Problem(message: "\(flag) needs a value")) }
            return .success(arguments[index])
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--label":
                switch value(for: argument) {
                case .success(let text): options.label = text
                case .failure(let problem): return .failure(problem)
                }
            case "--seconds":
                switch value(for: argument) {
                case .success(let text):
                    guard let seconds = Int(text), seconds > 0 else {
                        return .failure(Problem(message: "--seconds needs a positive number"))
                    }
                    options.seconds = seconds
                case .failure(let problem): return .failure(problem)
                }
            case "--playing":
                switch value(for: argument) {
                case .success(let text):
                    guard let playing = Playing(rawValue: text) else {
                        return .failure(Problem(message: "--playing needs music, spotify, browser, video, other or none"))
                    }
                    options.playing = playing
                case .failure(let problem): return .failure(problem)
                }
            case "--redact":
                options.showValues = false
            case "--show-values":
                options.showValues = true
            default:
                if argument.hasPrefix("--") { return .failure(Problem(message: "unknown option \(argument)")) }
                if options.command.isEmpty {
                    options.command = argument
                } else {
                    options.positional.append(argument)
                }
            }
            index += 1
        }
        guard !options.command.isEmpty else { return .failure(Problem(message: "no command")) }
        return .success(options)
    }
}

/// One run of one command: the PROBE and SYSTEM lines, STEP lines, the questions at the end,
/// the SUMMARY and ANSWER lines, and the closing line.
@MainActor
final class Session {
    let options: Options
    private let startedAt = Date()

    init(options: Options) {
        self.options = options
        Output.emit("PROBE", [
            ("mode", options.command),
            ("label", options.label),
            ("redact", options.showValues ? "no" : "yes"),
        ])
        Output.emit("SYSTEM", [
            ("macos", Session.macOSVersion()),
            ("arch", Session.machine()),
            ("hardened", Session.isHardened().map { $0 ? "yes" : "no" }),
        ])
    }

    /// Seconds since the session began, with one decimal.
    func elapsed() -> String {
        String(format: "%.1f", Date().timeIntervalSince(startedAt))
    }

    func step(_ text: String) {
        Output.emit("STEP " + text)
    }

    /// Asks a yes/no question, only when standard input is a terminal. An empty answer, or no
    /// terminal, is unknown (nil).
    func ask(_ question: String) -> Bool? {
        guard isatty(STDIN_FILENO) != 0 else { return nil }
        step("\(question) (y/n, Enter if you did not try it)")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        if answer.hasPrefix("y") { return true }
        if answer.hasPrefix("n") { return false }
        return nil
    }

    /// Asks for one of the given words, only when standard input is a terminal.
    func askChoice(_ question: String, choices: [String]) -> String? {
        guard isatty(STDIN_FILENO) != 0 else { return nil }
        step("\(question) (\(choices.joined(separator: ", ")); Enter if unknown)")
        guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        return choices.contains(answer) ? answer : nil
    }

    /// Writes the ANSWER line. Each value is a text or nil for unknown.
    func answer(
        playEvent: String? = nil, pauseEvent: String? = nil, skipEvent: String? = nil,
        seekEvent: String? = nil, keyToggled: String? = nil, keyApp: String? = nil
    ) {
        Output.emit("ANSWER", [
            ("playEvent", playEvent), ("pauseEvent", pauseEvent), ("skipEvent", skipEvent),
            ("seekEvent", seekEvent), ("keyToggled", keyToggled), ("keyApp", keyApp),
        ])
    }

    func end() {
        Output.emit("=== end of report ===")
    }

    // MARK: - Facts about the process

    static func macOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var text = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        if let build = sysctlString("kern.osversion") { text += "/\(build)" }
        return text
    }

    static func machine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Whether the running binary is signed with the hardened runtime (`CS_RUNTIME`).
    static func isHardened() -> Bool? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let raw = dictionary[kSecCodeInfoFlags as String] as? UInt32 else { return nil }
        return raw & 0x10000 != 0
    }
}

/// Runs the main run loop until the time is up or Ctrl-C, so a run that is stopped early still
/// writes its report.
@MainActor
func runMainLoop(seconds: Int) {
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler { CFRunLoopStop(CFRunLoopGetMain()) }
    source.resume()
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
        CFRunLoopStop(CFRunLoopGetMain())
    }
    CFRunLoopRun()
    source.cancel()
}

/// Runs every pure function on built-in data and compares the lines to literals.
enum Selftest {
    @MainActor
    static func run() -> Bool {
        var mismatches: [String] = []
        func check(_ name: String, _ actual: String, _ expected: String) {
            if actual != expected { mismatches.append("\(name): got \(actual) expected \(expected)") }
        }

        let musicPayload: [String: Any] = [
            "Name": "Some Song", "Artist": "Some Artist", "Album": "Some Album", "Total Time": 215_000,
            "Player State": "Playing", "Persistent ID": "ABCDEF", "Location": "file:///x.m4a",
        ]
        let spotifyPayload: [String: Any] = [
            "Name": "Other Song", "Artist": "Other Artist", "Album": "Other Album", "Duration": 180_000,
            "Playback Position": 12.5, "Player State": "Paused", "Track ID": "spotify:track:x",
        ]
        let iTunesPayload: [String: Any] = ["Name": "Old", "Player State": "Stopped"]
        let payloads: [(name: String, userInfo: [String: Any], keys: String, has: String)] = [
            (
                "com.apple.Music.playerInfo", musicPayload,
                "Album:String;Artist:String;Location:String;Name:String;Persistent ID:String;Player State:String;Total Time:Int",
                "name:y,artist:y,album:y,duration:y,position:n,location:y"
            ),
            (
                "com.spotify.client.PlaybackStateChanged", spotifyPayload,
                "Album:String;Artist:String;Duration:Int;Name:String;Playback Position:Double;Player State:String;Track ID:String",
                "name:y,artist:y,album:y,duration:y,position:y,location:n"
            ),
            (
                "com.apple.iTunes.playerInfo", iTunesPayload,
                "Name:String;Player State:String",
                "name:y,artist:n,album:n,duration:n,position:n,location:n"
            ),
        ]
        var music = PlayerObservation()
        var spotify = PlayerObservation()
        for payload in payloads {
            let inventory = PayloadInventory.inventory(payload.userInfo)
            let flags = PayloadInventory.flags(inventory)
            check("\(payload.name) keys", PayloadInventory.describe(inventory), payload.keys)
            check("\(payload.name) has", flags.has, payload.has)
            if payload.name.hasPrefix("com.spotify") { spotify.record(flags) } else { music.record(flags) }
        }
        check("redaction", PayloadInventory.redacted("Some Song"), "len=9")
        check("state", PayloadInventory.state(in: musicPayload) ?? "-", "Playing")
        check("state unknown", PayloadInventory.state(in: ["Player State": "Buffering"]) ?? "-", "-")

        check(
            "summary",
            Verdict.summaryLine(
                music: music, spotify: spotify, others: 1,
                source: Verdict.source(music: music, spotify: spotify), controls: nil, remote: nil
            ),
            "SUMMARY music=2 spotify=1 others=1 musicPosition=n spotifyPosition=y musicLocation=y source=GO controls=- remote=-"
        )

        let perlLine = "MEDIAREMOTE route=perl arch=arm64e loaded=y symbols=info:y;client:y;bundle:y;playing:y;notify:y result=keys:7 app=com.apple.Safari macos=27.2.0"
        let emptyLine = "MEDIAREMOTE route=direct arch=arm64 loaded=y symbols=info:y result=empty app=- macos=27.2.0"
        let observations = [perlLine, emptyLine, "NOTIFY n=1"].compactMap { RemoteObservation.parse(line: $0, label: "browser") }
        check("remote lines", String(observations.count), "2")
        check("remote verdict", Verdict.remote(observations).rawValue, "GO")
        check("remote direct only", Verdict.remote(observations.filter { $0.route == "direct" }).rawValue, "NO-GO")
        check("controls", Verdict.controls(musicToggled: true, spotifyToggled: nil).rawValue, "REDUCED-GO")

        mismatches += LocalChecks.selftestMismatches()

        for line in mismatches { Output.emit("mismatch: " + line) }
        Output.emit(mismatches.isEmpty ? "selftest ok" : "selftest MISMATCH")
        return mismatches.isEmpty
    }
}
