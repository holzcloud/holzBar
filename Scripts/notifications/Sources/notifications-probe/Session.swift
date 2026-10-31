//
//  Session.swift
//  notifications
//
//  One run of the probe: the PROBE and SYSTEM lines, the command's lines, the SUMMARY built
//  from the verdicts of the core, the end-of-run questions and the end line. The probe
//  prints no title, body or app name unless `--show-values` is given and writes no file.
//

import ApplicationServices
import Darwin
import Foundation
import NotificationProbeCore
import Security

/// Output goes through one lock and is written unbuffered, so a report that is cut off or
/// piped through `tee` is complete up to the last line.
enum Out {
    private static let lock = NSLock()

    static func emit(_ text: String) {
        lock.lock()
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        lock.unlock()
    }
}

enum Report {
    static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    static func millis(_ value: Double) -> String { String(format: "%.1f", value) }
}

/// The options of one run.
struct Options {
    var command: String
    var label = "-"
    var trigger = "T2"
    var title: String?
    var body: String?
    var showValues = false
    var seconds = 90
}

enum Session {
    static func run(_ options: Options) -> Int32 {
        Out.emit(ProbeLine.line("PROBE", [
            ("mode", options.command),
            ("label", options.label),
            ("redact", Report.yesNo(!options.showValues)),
        ]))
        Out.emit(systemLine())

        var routeA: String?
        var decision: String?
        var answers = Answers()
        switch options.command {
        case "ax-banner":
            let outcome = Banner.run(options)
            if let code = outcome.exitCode {
                Out.emit(ProbeLine.endOfReport)
                return code
            }
            if let observation = outcome.observation {
                let judgement = Verdict.single(observation)
                routeA = Verdict.text(judgement)
                decision = Verdict.decision(routeA: judgement.result)
                answers = askBannerQuestions()
            }
        default:
            break
        }

        Out.emit(ProbeLine.summary(routeA: routeA ?? "not run", routeB: "not run", decision: decision))
        Out.emit(ProbeLine.line("ANSWER", [
            ("bannerSeen", answers.bannerSeen),
            ("focusOn", answers.focusOn),
            ("alertStyle", answers.alertStyle),
        ]))
        Out.emit(ProbeLine.endOfReport)
        return 0
    }

    // MARK: SYSTEM

    private static func systemLine() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let macos = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return ProbeLine.line("SYSTEM", [
            ("macos", macos),
            ("hardened", isHardened().map(Report.yesNo)),
            ("trusted", Report.yesNo(AXIsProcessTrusted())),
        ])
    }

    /// Whether the running binary was signed with the hardened runtime.
    private static func isHardened() -> Bool? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let signingFlags = dictionary[kSecCodeInfoFlags as String] as? UInt32
        else {
            return nil
        }
        // kSecCodeSignatureRuntime
        return signingFlags & 0x10000 != 0
    }

    // MARK: Questions

    struct Answers {
        var bannerSeen: String?
        var focusOn: String?
        var alertStyle: String?
    }

    /// The end-of-run questions, asked only on a terminal.
    private static func askBannerQuestions() -> Answers {
        guard isatty(STDIN_FILENO) != 0 else {
            return Answers()
        }
        var answers = Answers()
        answers.bannerSeen = askYesNo("did a notification banner appear on the screen during the run")
        answers.focusOn = askYesNo("was a Focus or Do Not Disturb on")
        answers.alertStyle = askYesNo("was the notification an alert that waits for a click, rather than a banner")
        return answers
    }

    private static func askYesNo(_ question: String) -> String? {
        Out.emit("STEP answer y or n and press Return: \(question)")
        switch readLine()?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "y", "yes": return "y"
        case "n", "no": return "n"
        default: return nil
        }
    }
}

// MARK: selftest

enum Selftest {
    /// Runs the tree summary, the text matcher, the verdicts and the line format on built-in
    /// data: no Accessibility, no process and no permission. Exits 0 only when every line
    /// matches.
    static func run() -> Int32 {
        var failures: [String] = []
        func check(_ name: String, _ actual: String, _ expected: String) {
            if actual != expected {
                failures.append("\(name): got \(actual) expected \(expected)")
            }
        }

        let banner = RawNode(
            role: "AXGroup",
            subrole: "AXNotificationCenterBanner",
            texts: [],
            children: [
                RawNode(role: "AXStaticText", texts: ["Probe title"]),
                RawNode(role: "AXStaticText", texts: ["Probe body text"]),
                RawNode(role: "AXImage"),
            ]
        )
        let nodes = AXTree.summarise(banner)
        check("nodes", String(nodes.count), "4")
        check("textNodes", String(AXTree.textNodeCount(nodes)), "2")
        let texts = AXTree.allTexts(banner)
        let titleMatch = texts.contains { TextMatcher.matches($0, expected: "probe TITLE") }
        let bodyMatch = texts.contains { TextMatcher.matches($0, expected: "body text") }
        check("matches", "\(titleMatch) \(bodyMatch)", "true true")

        let sample = ReadSample(
            eventMs: 420, readMs: 12, textNodes: AXTree.textNodeCount(nodes),
            titleMatched: titleMatch, bodyMatched: bodyMatch
        )
        let observation = Verdict.observe(posted: true, eventCount: 1, samples: [sample])
        let judgement = Verdict.single(observation)
        check(
            "summary",
            ProbeLine.summary(
                routeA: Verdict.text(judgement),
                routeB: "not run",
                decision: Verdict.decision(routeA: judgement.result)
            ),
            "SUMMARY routeA=GO routeB=\"not run\" decision=go"
        )

        var slow = observation
        slow.latencyMs = 2000
        check("slow", Verdict.text(Verdict.single(slow)), "REDUCED-GO (latency between 1.5 and 5 seconds)")
        check("none", Verdict.text(Verdict.single(Verdict.observe(posted: false, eventCount: 0, samples: []))), "NO-GO (no event arrived)")
        check(
            "node",
            ProbeLine.line("NODE", [
                ("n", "1"), ("depth", "1"), ("role", "AXStaticText"), ("subrole", nil),
                ("identifier", nil), ("textLen", "11"),
            ]),
            "NODE n=1 depth=1 role=AXStaticText subrole=- identifier=- textLen=11"
        )

        if failures.isEmpty {
            Out.emit("selftest ok")
            return 0
        }
        for failure in failures {
            Out.emit("selftest FAIL \(failure)")
        }
        return 4
    }
}
