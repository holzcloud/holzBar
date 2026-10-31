//
//  MediaRemoteCheck.swift
//  now-playing
//

import Foundation
import NowPlayingProbeCore
import RemoteProbeLib

/// `mediaremote direct` and `mediaremote perl DYLIB`: the measurement for D-08. The direct route
/// runs the probe library's code in the probe's own process; the perl route loads the same code
/// as a dynamic library into /usr/bin/perl, the platform process MediaRemote still serves. The
/// output has the count and the names of the dictionary's keys and the bundle identifier of the
/// app MediaRemote names, never a value of the dictionary.
@MainActor
enum MediaRemoteCheck {
    /// The perl script, a constant (no file ships): loads the library with DynaLoader, finds the
    /// exported function and calls it. On a loader failure it prints the loader's own text.
    private static let script = """
    use DynaLoader;
    my ($path, $function) = @ARGV;
    my $library = DynaLoader::dl_load_file($path, 0);
    if (!$library) { print "LOADFAIL ", DynaLoader::dl_error(), "\\n"; exit 3; }
    my $symbol = DynaLoader::dl_find_symbol($library, $function);
    if (!$symbol) { print "SYMBOLFAIL ", DynaLoader::dl_error(), "\\n"; exit 4; }
    my $probe = DynaLoader::dl_install_xsub('main::probe', $symbol);
    &$probe();
    """

    private static let function = "nowplaying_probe_get"
    private static let perlTimeout: TimeInterval = 10

    /// Whether the arguments are usable; the caller exits 2 otherwise.
    static func validate(_ options: Options) -> Problem? {
        switch options.positional.first {
        case "direct":
            return options.positional.count == 1 ? nil : Problem(message: "mediaremote direct takes no path")
        case "perl":
            guard options.positional.count == 2 else { return Problem(message: "mediaremote perl needs the path of the library") }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: options.positional[1], isDirectory: &isDirectory), !isDirectory.boolValue else {
                return Problem(message: "no library at that path")
            }
            return nil
        default:
            return Problem(message: "mediaremote needs direct or perl DYLIB")
        }
    }

    static func run(session: Session) {
        let route = session.options.positional[0]
        session.step("Reading the now-playing information once, read-only, through the \(route) route. No value is printed.")
        let label = session.options.playing.rawValue

        var observation: RemoteObservation?
        if route == "direct" {
            let report = remoteProbeReport()
            observation = emit(from: report, route: "direct", dylibArchitecture: nil, loaderError: nil, label: label)
        } else {
            let path = session.options.positional[1]
            let arch = machOArchitecture(path: path)
            let outcome = runPerl(dylib: path)
            switch outcome {
            case .report(let report):
                observation = emit(from: report, route: "perl", dylibArchitecture: arch, loaderError: nil, label: label)
                Output.emit("LOADER", [("arch", arch), ("status", "ok"), ("error", nil)])
            case .loaderFailure(let kind, let text):
                let result = kind == "SYMBOLFAIL" ? "symbolfail" : "loadfail"
                observation = emit(
                    from: "REMOTEPROBE arch=\(arch ?? "-") loaded=\(kind == "SYMBOLFAIL" ? "y" : "n") symbols=- result=\(result) app=- keys=-",
                    route: "perl", dylibArchitecture: arch, loaderError: text, label: label
                )
                Output.emit("LOADER", [("arch", arch), ("status", "failed"), ("error", text)])
            case .timeout:
                observation = emit(
                    from: "REMOTEPROBE arch=\(arch ?? "-") loaded=y symbols=- result=timeout app=- keys=-",
                    route: "perl", dylibArchitecture: arch, loaderError: nil, label: label
                )
                Output.emit("LOADER", [("arch", arch), ("status", "ok"), ("error", nil)])
            case .failure(let text):
                observation = emit(
                    from: "REMOTEPROBE arch=\(arch ?? "-") loaded=y symbols=- result=error app=- keys=-",
                    route: "perl", dylibArchitecture: arch, loaderError: nil, label: label
                )
                Output.emit("LOADER", [("arch", arch), ("status", "ok"), ("error", text)])
            }
        }

        // Only the perl route counts for REMOTE; a direct run leaves the result unset.
        let remote = route == "perl" ? observation.map { Verdict.remote([$0]) } : nil
        Output.emit(Verdict.summaryLine(
            music: nil, spotify: nil, others: 0, source: nil, controls: nil, remote: remote
        ))
        if route == "direct" {
            session.step("The direct route is recorded as evidence only; it never counts for REMOTE.")
        } else if session.options.playing == .none {
            session.step("No --playing label was given: keys from an unknown app count only as REDUCED-GO.")
        }
        session.answer()
        session.end()
    }

    // MARK: - Lines

    /// Turns a REMOTEPROBE line into the MEDIAREMOTE line (and REMOTEKEYS when keys were counted).
    private static func emit(
        from report: String, route: String, dylibArchitecture: String?, loaderError: String?, label: String
    ) -> RemoteObservation? {
        var values: [String: String] = [:]
        for field in report.split(separator: " ").dropFirst() {
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
        let line = ReportLine.format(tag: "MEDIAREMOTE", [
            ("route", route),
            ("arch", values["arch"] ?? dylibArchitecture),
            ("loaded", values["loaded"]),
            ("symbols", values["symbols"]),
            ("result", values["result"]),
            ("app", values["app"]),
            ("macos", Session.macOSVersion()),
        ])
        Output.emit(line)
        if values["result"]?.hasPrefix("keys:") == true, let names = values["keys"], names != "-" {
            Output.emit("REMOTEKEYS", [("names", names)])
        }
        return RemoteObservation.parse(line: line, label: label)
    }

    // MARK: - perl

    private enum PerlOutcome {
        case report(String)
        case loaderFailure(kind: String, text: String)
        case timeout
        case failure(String)
    }

    /// Runs /usr/bin/perl with the script and a fixed minimal environment, standard input and
    /// error from the null device, and ends it after ten seconds.
    private static func runPerl(dylib: String) -> PerlOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", script, "--", dylib, function]
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return .failure("could not start perl")
        }
        if finished.wait(timeout: .now() + perlTimeout) == .timedOut {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
            return .timeout
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n").map(String.init)
        if let failure = lines.first(where: { $0.hasPrefix("LOADFAIL") || $0.hasPrefix("SYMBOLFAIL") }) {
            let kind = failure.hasPrefix("LOADFAIL") ? "LOADFAIL" : "SYMBOLFAIL"
            return .loaderFailure(kind: kind, text: String(failure.dropFirst(kind.count)).trimmingCharacters(in: .whitespaces))
        }
        if let report = lines.first(where: { $0.hasPrefix("REMOTEPROBE ") }) {
            return .report(report)
        }
        return .failure("perl ended with status \(process.terminationStatus) and no report")
    }

    // MARK: - The library's architecture

    /// The architecture of a thin Mach-O file from its header: arm64, arm64e, x86_64 or nil.
    static func machOArchitecture(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count == 12 else { return nil }
        func word(_ offset: Int) -> UInt32 {
            header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        }
        guard word(0) == 0xfeed_facf else { return nil }
        let cpu = word(4)
        let subtype = word(8) & 0x00ff_ffff
        switch cpu {
        case 0x0100_000c: return subtype == 2 ? "arm64e" : "arm64"
        case 0x0100_0007: return "x86_64"
        default: return nil
        }
    }
}
