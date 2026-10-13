//
//  main.swift
//  holzBar
//

// Phase 24 spike (Preview, throwaway, not part of holzBar.app): can SwiftUI's reordering API
// (macOS 27) carry the Menu Bar Layout pane's three rows, and what would a replacement bring
// along?
//
// Commands:
//   check     write whether SwiftUI reordering exists on this Mac; no window
//   selftest  run the move rules on built-in data; no window and no permission
//   count     the C1 desk check: the AppKit Layout bar's code against the code a SwiftUI path
//             would carry (reads source files under --repo, writes numbers)
//   run       open one window with the three rows of fake items (macOS 27 only; stops with
//             exit 7 below it)
//
// The spike asks for no permission, reads nothing of other apps, has no network code and writes
// nothing to disk; every line goes to standard output.
//
// Build and run:
//   swift build -c release --package-path Scripts/layout-reorder
//   Scripts/layout-reorder/.build/release/layout-reorder-spike --help
import AppKit
import LayoutReorderCore
import Observation
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - Options

struct Options {
    var command = ""
    var label = "unlabelled"
    var repo = "."

    static let usage = [
        "usage: layout-reorder-spike <command> [options]",
        "",
        "commands:",
        "  check     whether SwiftUI reordering exists on this Mac (no window)",
        "  selftest  run the move rules on built-in data (no window, no permission)",
        "  count     the C1 desk check: AppKit Layout bar code against the SwiftUI path's carried code",
        "  run       open the window with three reorderable rows (macOS 27 only)",
        "",
        "options:",
        "  --label <text>   what this run is, written to the report (default: unlabelled)",
        "  --repo <dir>     count only: the repository to read (default: .)",
        "  --help           write this text",
    ].joined(separator: "\n")

    /// Reads the arguments; `--help` exits 0, anything unknown writes the usage to standard error
    /// and exits 2.
    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var rest = Array(arguments.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            print(usage)
            exit(0)
        }
        guard let command = rest.first, ["check", "selftest", "count", "run"].contains(command) else {
            fail("unknown or missing command")
        }
        options.command = command
        rest.removeFirst()
        while !rest.isEmpty {
            let option = rest.removeFirst()
            switch option {
            case "--label":
                guard !rest.isEmpty else {
                    fail("\(option) needs a value")
                }
                options.label = rest.removeFirst()
            case "--repo":
                guard command == "count" else {
                    fail("--repo is only for count")
                }
                guard !rest.isEmpty else {
                    fail("\(option) needs a value")
                }
                options.repo = rest.removeFirst()
            default:
                fail("unknown option \(option)")
            }
        }
        return options
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n\(usage)\n".utf8))
        exit(2)
    }
}

// MARK: - Report lines

let endLine = "=== end of report ==="

/// Whether this Mac has SwiftUI reordering.
var reorderAvailable: Bool {
    if #available(macOS 27.0, *) {
        return true
    }
    return false
}

func displayCount() -> Int {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success else {
        return 0
    }
    return Int(count)
}

func spikeLine(mode: String, label: String) -> String {
    var line = ReportLine("SPIKE")
    line.add("mode", mode)
    line.add("label", label)
    return line.text
}

func systemLine() -> String {
    var line = ReportLine("SYSTEM")
    line.add("macos", ProcessInfo.processInfo.operatingSystemVersionString)
    line.add("reorder", reorderAvailable ? "available" : "unavailable")
    line.add("displays", displayCount())
    return line.text
}

func rowsLine(_ bar: FakeBar) -> String {
    var line = ReportLine("ROWS")
    line.add("items", bar.itemCount)
    for section in SpikeSection.allCases {
        line.add(section.rawValue, bar.rows[section]?.count ?? 0)
    }
    return line.text
}

/// The MOVE line of one request, written by `selftest` and `run` alike.
func moveLine(n: Int, via: String, request: ReorderRequest, outcome: ReorderOutcome, bar: FakeBar) -> String {
    var line = ReportLine("MOVE")
    line.add("n", n)
    line.add("via", via)
    line.add("sources", request.sources.joined(separator: ","))
    line.add("from", request.sources.map { bar.section(of: $0)?.rawValue ?? "-" }.joined(separator: ","))
    line.add("to", request.target.rawValue)
    line.add("position", request.positionText)
    line.add("accepted", outcome.moves.count)
    line.add("reason", outcome.refusals.map(\.reason.rawValue).joined(separator: ","))
    line.add("intent", outcome.intents.joined(separator: ";"))
    return line.text
}

// MARK: - selftest

/// One request of `selftest` with what the rules must answer.
struct SelftestCase {
    let request: ReorderRequest
    let accepted: Int
    let reason: String
    let intent: String?
}

func selftest(label: String) -> Never {
    var bar = FakeBar.make(itemCount: 12)
    print(spikeLine(mode: "selftest", label: label))
    print(rowsLine(bar))
    let cases = [
        SelftestCase(
            request: ReorderRequest(sources: ["app.1"], target: .hidden, position: .end),
            accepted: 1,
            reason: "-",
            intent: "LayoutBarMoves.setSection(com.example.app1,.hidden)"
        ),
        SelftestCase(
            request: ReorderRequest(sources: ["twoitems.0"], target: .alwaysHidden, position: .before("spacer.0")),
            accepted: 1,
            reason: "-",
            intent: "LayoutBarMoves.setSection(com.example.twoitems,.alwaysHidden)"
        ),
        SelftestCase(
            request: ReorderRequest(sources: ["app.2"], target: .visible, position: .end),
            accepted: 0,
            reason: "sameSection",
            intent: nil
        ),
        SelftestCase(
            request: ReorderRequest(sources: ["system.clock"], target: .hidden, position: .end),
            accepted: 0,
            reason: "notMovable",
            intent: nil
        ),
        SelftestCase(
            request: ReorderRequest(sources: ["holzbar.icon"], target: .hidden, position: .end),
            accepted: 0,
            reason: "controlItem",
            intent: nil
        ),
        SelftestCase(
            request: ReorderRequest(sources: ["unknown.0"], target: .visible, position: .end),
            accepted: 0,
            reason: "noApp",
            intent: nil
        ),
        SelftestCase(
            request: ReorderRequest(sources: ["busy.0"], target: .visible, position: .end),
            accepted: 0,
            reason: "unresponsive",
            intent: nil
        ),
    ]
    var problems = [String]()
    for (index, expected) in cases.enumerated() {
        let outcome = ReorderIntent.outcome(for: expected.request, in: bar)
        print(moveLine(n: index + 1, via: "selftest", request: expected.request, outcome: outcome, bar: bar))
        let reason = outcome.refusals.map(\.reason.rawValue).joined(separator: ",")
        if outcome.moves.count != expected.accepted {
            problems.append("request \(index + 1) accepted \(outcome.moves.count), not \(expected.accepted)")
        }
        if (reason.isEmpty ? "-" : reason) != expected.reason {
            problems.append("request \(index + 1) reason \(reason), not \(expected.reason)")
        }
        if let intent = expected.intent, outcome.intents != [intent] {
            problems.append("request \(index + 1) intent \(outcome.intents)")
        }
        bar = bar.applying(outcome)
    }
    let expectedRows: [SpikeSection: [String]] = [
        .visible: ["holzbar.icon", "system.clock", "app.2", "app.3"],
        .hidden: ["unknown.0", "busy.0", "widget.battery", "group.work", "app.1"],
        .alwaysHidden: ["twoitems.0", "twoitems.1", "spacer.0"],
    ]
    for section in SpikeSection.allCases where bar.rows[section]?.map(\.id) != expectedRows[section] {
        problems.append("row \(section.rawValue) is \(bar.rows[section]?.map(\.id) ?? [])")
    }
    print(rowsLine(bar))
    print(endLine)
    if problems.isEmpty {
        print("selftest ok")
        exit(0)
    }
    print("selftest FAILED: \(problems.joined(separator: "; "))")
    exit(4)
}

// MARK: - count

/// One file of the C1 count: `appkit` for the Layout bar, `carried` for what a replacement brings.
struct CountedFile {
    let role: String
    let path: String
    let text: String
}

func count(repo: String) -> Never {
    let root = URL(fileURLWithPath: repo, isDirectory: true)
    let barDirectory = "holzBar/MenuBar/LayoutBar"
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(barDirectory).path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
        .sorted()
    if names.isEmpty {
        FileHandle.standardError.write(Data("no Swift file in \(barDirectory) under \(repo)\n".utf8))
        exit(6)
    }
    let carriedPaths = [
        "Scripts/layout-reorder/Sources/LayoutReorderCore/ReorderIntent.swift",
        "Scripts/layout-reorder/Sources/layout-reorder-spike/ReorderSectionsView.swift",
    ]
    let wanted = names.map { ("appkit", "\(barDirectory)/\($0)") } + carriedPaths.map { ("carried", $0) }
    var files = [CountedFile]()
    for (role, path) in wanted {
        guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read \(path) under \(repo)\n".utf8))
            exit(6)
        }
        files.append(CountedFile(role: role, path: path, text: text))
    }
    for file in files {
        var line = ReportLine("COUNTFILE")
        line.add("role", file.role)
        line.add("path", file.path)
        line.add("code", CodeCount.codeLines(file.text))
        line.add("scoped27", CodeCount.scopedLines(file.text))
        print(line.text)
    }
    let report = CodeCount.report(
        appKit: files.filter { $0.role == "appkit" }.map(\.text),
        carried: files.filter { $0.role == "carried" }.map(\.text)
    )
    var line = ReportLine("COUNT")
    line.add("appKitCode", report.appKitCode)
    line.add("deletableMax", report.deletableMax)
    line.add("newMin", report.newMin)
    line.add("ratio", report.ratio, decimals: 2)
    line.add("threshold", report.threshold, decimals: 2)
    line.add("meets", report.meets)
    print(line.text)
    print(endLine)
    exit(0)
}

// MARK: - run

/// The state of the window: the fake bar, which asks the rules for every drop.
@MainActor @Observable
final class SpikeModel {
    var bar: FakeBar
    private(set) var moveCount = 0

    init(bar: FakeBar) {
        self.bar = bar
    }

    func handle(_ request: ReorderRequest, via: String) {
        let outcome = ReorderIntent.outcome(for: request, in: bar)
        moveCount += 1
        print(moveLine(n: moveCount, via: via, request: request, outcome: outcome, bar: bar))
        bar = bar.applying(outcome)
    }
}

func run(label: String) -> Never {
    print(spikeLine(mode: "run", label: label))
    print(systemLine())
    guard #available(macOS 27.0, *) else {
        var skip = ReportLine("SKIP")
        skip.add("reason", "SwiftUI reordering needs macOS 27")
        print(skip.text)
        print(endLine)
        exit(7)
    }
    let model = SpikeModel(bar: FakeBar.make(itemCount: 12))
    print(rowsLine(model.bar))
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Layout reorder spike (Preview)"
    window.contentView = NSHostingView(rootView: ReorderSectionsView(model: model))
    window.center()
    window.isReleasedWhenClosed = false
    NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: window,
        queue: .main
    ) { _ in
        print(endLine)
        exit(0)
    }
    window.makeKeyAndOrderFront(nil)
    application.activate()
    application.run()
    exit(0)
}

// MARK: - main

let options = Options.parse(CommandLine.arguments)
switch options.command {
case "check":
    print(spikeLine(mode: "check", label: options.label))
    print(systemLine())
    print(endLine)
    exit(0)
case "selftest":
    selftest(label: options.label)
case "count":
    count(repo: options.repo)
default:
    run(label: options.label)
}
