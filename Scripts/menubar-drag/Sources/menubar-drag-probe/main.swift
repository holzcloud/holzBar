//
//  main.swift
//  holzBar
//

// Phase 77 spike (Preview, throwaway, not part of holzBar.app): what happens when holzBar turns a
// plain drag on a menu bar item into a Command-drag, so that items can be moved without holding
// Command?
//
// Commands:
//   bar       read the menu bar once and write what was found (read-only)
//   selftest  run the measurement on built-in data; needs no permission
//   a1        mechanism A, rewrite: while it runs, every drag that starts on an app item gets the
//             Command flag added to the user's own events
//   a2        mechanism A, hold and decide: a press on an app item waits; moving it sideways makes
//             a Command-drag, releasing it makes a normal click
//
// `a1` and `a2` change how the menu bar reacts to the mouse while they run (a1: clicks on app
// items do not open their menus; a2: a press on an app item waits for the move or the release)
// and end by themselves, after --seconds, after --gestures drags or at Ctrl-C. The
// terminal needs Accessibility (System Settings > Privacy & Security > Accessibility). The probe
// has no network code and writes nothing to disk; every line goes to standard output.
//
// Build and run:
//   swift build -c release --package-path Scripts/menubar-drag
//   Scripts/menubar-drag/.build/release/menubar-drag-probe --help
import AppKit
@preconcurrency import ApplicationServices
import MenuBarDragCore

// MARK: - Options

struct Options {
    var command = ""
    var label = "unlabelled"
    var seconds = 180
    var gestures = 12
    var redact = false

    static let usage = [
        "usage: menubar-drag-probe <command> [options]",
        "",
        "commands:",
        "  bar       read the menu bar once and write the items found",
        "  selftest  run the measurement on built-in data (no permission needed)",
        "  a1        mechanism A, rewrite: drags on app items get the Command flag added",
        "  a2        mechanism A, hold and decide: a press on an app item waits; moving it sideways makes a "
            + "Command-drag, releasing makes a normal click",
        "",
        "options:",
        "  --label <text>   what this run is, written to the report (default: unlabelled)",
        "  --seconds <n>    end a live command after n seconds (default: 180)",
        "  --gestures <n>   end a live command after n drags (default: 12)",
        "  --redact         write non-Apple apps other than holzBar as app1, app2, ...",
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
        guard let command = rest.first, ["bar", "selftest", "a1", "a2"].contains(command) else {
            fail("unknown or missing command")
        }
        options.command = command
        rest.removeFirst()
        while !rest.isEmpty {
            let option = rest.removeFirst()
            switch option {
            case "--label":
                options.label = value(of: option, in: &rest)
            case "--seconds":
                options.seconds = max(1, number(of: option, in: &rest))
            case "--gestures":
                options.gestures = max(1, number(of: option, in: &rest))
            case "--redact":
                options.redact = true
            default:
                fail("unknown option \(option)")
            }
        }
        return options
    }

    private static func value(of option: String, in rest: inout [String]) -> String {
        guard !rest.isEmpty else {
            fail("\(option) needs a value")
        }
        return rest.removeFirst()
    }

    private static func number(of option: String, in rest: inout [String]) -> Int {
        guard let number = Int(value(of: option, in: &rest)) else {
            fail("\(option) needs a whole number")
        }
        return number
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n\(usage)\n".utf8))
        exit(2)
    }
}

// MARK: - Reading the bar

/// Reads the menu bar through Accessibility: every process publishes its items under its extras
/// menu bar. Reads belong off the main actor and never inside an event tap callback.
nonisolated enum BarReader {
    private static let largestMagnitude: CGFloat = 1_000_000

    static func snapshot(near point: CGPoint?, barHeights: [UInt32: CGFloat], generation: Generation) -> BarSnapshot {
        let display = displayID(containing: point)
        let bounds = CGDisplayBounds(display)
        var items = [BarItem]()
        for application in NSWorkspace.shared.runningApplications {
            guard let owner = application.bundleIdentifier else {
                continue
            }
            let element = AXUIElementCreateApplication(application.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.4)
            guard
                let bar = value(element, kAXExtrasMenuBarAttribute),
                CFGetTypeID(bar) == AXUIElementGetTypeID(),
                let children = value(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] // swiftlint:disable:this force_cast
            else {
                continue
            }
            for (index, child) in children.enumerated() {
                guard let frame = frame(of: child), bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
                    continue
                }
                let identifier = (value(child, kAXIdentifierAttribute) as? String) ?? ""
                items.append(BarItem(
                    id: "\(owner)#\(index)",
                    owner: owner,
                    kind: kind(owner: owner, identifier: identifier),
                    frame: frame
                ))
            }
        }
        return BarSnapshot(
            generation: generation,
            displayID: display,
            displayBounds: bounds,
            barMaxY: bounds.minY + (barHeights[display] ?? 24),
            items: items
        )
    }

    /// The height of the menu bar on each display, from the screens' frames.
    @MainActor
    static func barHeights() -> [UInt32: CGFloat] {
        var heights = [UInt32: CGFloat]()
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            heights[number.uint32Value] = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        }
        return heights
    }

    private static func kind(owner: String, identifier: String) -> BarItem.Kind {
        if owner == "com.holzcloud.holzBar" {
            switch identifier {
            case "holzBar.ControlItem.Visible": return .holzBarIcon
            case "holzBar.ControlItem.Hidden": return .hiddenDivider
            case "holzBar.ControlItem.AlwaysHidden": return .alwaysHiddenDivider
            default: return .holzBarOther
            }
        }
        return owner.hasPrefix("com.apple.") ? .system : .app
    }

    private static func displayID(containing point: CGPoint?) -> UInt32 {
        guard let point else {
            return CGMainDisplayID()
        }
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else {
            return CGMainDisplayID()
        }
        return display
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard
            let positionValue = value(element, kAXPositionAttribute),
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            let sizeValue = value(element, kAXSizeAttribute),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position), // swiftlint:disable:this force_cast
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) // swiftlint:disable:this force_cast
        else {
            return nil
        }
        // The owning process reports these values, so a NaN or a huge one is turned away here.
        let values = [position.x, position.y, size.width, size.height]
        guard values.allSatisfy({ $0.isFinite && abs($0) < largestMagnitude }), size.width >= 0, size.height >= 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }
}

// MARK: - Output

/// The lines of the report, built in the output contract's key order.
enum ProbeOutput {
    static var generation: Generation {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
            ? .macOS27
            : .before27
    }

    static func probeLine(mode: String, label: String) -> ReportLine {
        var line = ReportLine("PROBE")
        line.add("mode", mode)
        line.add("label", label)
        return line
    }

    static func systemLine(generation: Generation) -> ReportLine {
        var line = ReportLine("SYSTEM")
        line.add("macos", ProcessInfo.processInfo.operatingSystemVersionString)
        line.add("generation", generation.rawValue)
        line.add("displays", NSScreen.screens.count)
        line.add("notch", NSScreen.screens.contains { $0.safeAreaInsets.top > 0 })
        return line
    }

    static func barLine(_ snapshot: BarSnapshot) -> ReportLine {
        func presence(_ kind: BarItem.Kind) -> String {
            snapshot.items.contains { $0.kind == kind && $0.counts } ? "present" : "absent"
        }
        var line = ReportLine("BAR")
        line.add("display", Int(snapshot.displayID))
        line.add("items", snapshot.items.count)
        line.add("counted", snapshot.orderedIDs().count)
        line.add("hiddenDivider", presence(.hiddenDivider))
        line.add("alwaysHiddenDivider", presence(.alwaysHiddenDivider))
        line.add("icon", presence(.holzBarIcon))
        return line
    }

    static func itemLine(index: Int, item: BarItem, in snapshot: BarSnapshot, shownID: String) -> ReportLine {
        var line = ReportLine("ITEM")
        line.add("i", index)
        line.add("id", shownID)
        line.add("kind", item.kind.rawValue)
        line.add("x", Int(item.frame.minX.rounded()))
        line.add("w", Int(item.frame.width.rounded()))
        line.add("section", snapshot.positionalSection(of: item)?.rawValue ?? "-")
        return line
    }

    /// `<section or ->/<index or ->`
    private static func place(section: BarSection?, index: Int?) -> String {
        "\(section?.rawValue ?? "-")/\(index.map { String($0) } ?? "-")"
    }

    static func resultLine(
        mech: String,
        n: Int,
        dragged: String,
        result: SettleResult,
        drop: CGFloat,
        commandHeld: Bool,
        executed: String,
        tapMaxUs: Int?
    ) -> ReportLine {
        var line = ReportLine("RESULT")
        line.add("mech", mech)
        line.add("n", n)
        line.add("dragged", dragged)
        line.add("from", place(section: result.fromSection, index: result.fromIndex))
        line.add("to", place(section: result.toSection, index: result.toIndex))
        line.add("drop", Int(drop.rounded()))
        line.add("commandHeld", commandHeld)
        line.add("moved", result.moved)
        line.add("scope", result.scope.rawValue)
        line.add("settleMs", result.settleMs)
        line.add("bounces", result.bounces)
        line.add("vanished", result.vanished)
        line.add("persisted", result.persisted)
        line.add("intent", "-")
        line.add("landed", "-")
        line.add("executed", executed)
        line.add("retried", "-")
        line.add("tapMaxUs", tapMaxUs)
        return line
    }
}

extension ProbeOutput {
    static func clickLine(mech: String, n: Int, item: String, record: ClickRecord) -> ReportLine {
        var line = ReportLine("CLICK")
        line.add("mech", mech)
        line.add("n", n)
        line.add("item", item)
        line.add("replayDelayMs", record.replayDelayMs)
        line.add("kind", record.kind.rawValue)
        return line
    }
}

let endLine = "=== end of report ==="

func requireAccessibility() {
    guard !AXIsProcessTrusted() else {
        return
    }
    FileHandle.standardError.write(Data("""
    This terminal has no Accessibility permission. System Settings > Privacy & Security > \
    Accessibility: add your terminal app, switch it on, quit the terminal (Cmd-Q) and open it again.

    """.utf8))
    exit(3)
}

// MARK: - selftest

/// Evaluates a built-in drag (b moves right of c at 100 ms and stays) and writes its RESULT line.
func runSelftest(_ options: Options) -> Int32 {
    func item(_ owner: String, _ kind: BarItem.Kind, x: CGFloat, width: CGFloat = 30) -> BarItem {
        BarItem(id: "\(owner)#0", owner: owner, kind: kind, frame: CGRect(x: x, y: 0, width: width, height: 24))
    }
    func bar(bX: CGFloat, cX: CGFloat) -> BarSnapshot {
        BarSnapshot(
            generation: .before27,
            displayID: 1,
            displayBounds: CGRect(x: 0, y: 0, width: 1512, height: 982),
            barMaxY: 24,
            items: [
                item("com.holzcloud.holzBar.alwaysHidden", .alwaysHiddenDivider, x: 250, width: 18),
                item("com.example.a", .app, x: 280),
                item("com.holzcloud.holzBar.hidden", .hiddenDivider, x: 380, width: 18),
                item("com.example.b", .app, x: bX),
                item("com.example.c", .app, x: cX),
                item("com.holzcloud.holzBar", .holzBarIcon, x: 500, width: 26),
                item("com.apple.controlcenter", .system, x: 1300, width: 80),
            ]
        )
    }
    let before = bar(bX: 420, cX: 460)
    let after = bar(bX: 460, cX: 420)
    let samples = SettleSeries.offsetsMs.filter { $0 <= 2000 }.map {
        SettleSeries.Sample(offsetMs: $0, snapshot: $0 < 100 ? before : after)
    }
    let dragged = "com.example.b#0"
    let result = SettleSeries.evaluate(before: before, draggedID: dragged, samples: samples)
    let line = ProbeOutput.resultLine(
        mech: "selftest",
        n: 1,
        dragged: dragged,
        result: result,
        drop: 485,
        commandHeld: false,
        executed: "none",
        tapMaxUs: nil
    )
    print(line.text)
    var summary = RunSummary()
    summary.add(result, landed: nil, refused: false)
    let summaryLine = summary.line(mechanism: "selftest", generation: .before27)
    print(summaryLine.text)
    let checks: [(String, Bool)] = [
        ("summary drags", summaryLine.text.contains(" drags=1 ")),
        ("summary moved", summaryLine.text.contains(" moved=1 ")),
        ("moved", result.moved),
        ("scope", result.scope == .reorder),
        ("settleMs", result.settleMs == 100),
        ("bounces", result.bounces == 0),
        ("vanished", !result.vanished),
    ]
    if let failed = checks.first(where: { !$0.1 }) {
        print("selftest FAILED: \(failed.0)")
        return 4
    }
    print("selftest ok")
    return 0
}

// MARK: - bar

func runBar(_ options: Options) -> Int32 {
    let generation = ProbeOutput.generation
    print(ProbeOutput.probeLine(mode: "bar", label: options.label).text)
    print(ProbeOutput.systemLine(generation: generation).text)
    let snapshot = BarReader.snapshot(
        near: CGEvent(source: nil)?.location,
        barHeights: BarReader.barHeights(),
        generation: generation
    )
    print(ProbeOutput.barLine(snapshot).text)
    var redactor = Redactor(enabled: options.redact)
    for (index, item) in snapshot.items.filter(\.counts).enumerated() {
        print(ProbeOutput.itemLine(index: index, item: item, in: snapshot, shownID: redactor.shownID(item.id)).text)
    }
    print(endLine)
    return snapshot.items.isEmpty ? 5 : 0
}

// MARK: - a1 and a2

func runLive(_ options: Options) -> Never {
    let generation = ProbeOutput.generation
    let snapshot = BarReader.snapshot(
        near: CGEvent(source: nil)?.location,
        barHeights: BarReader.barHeights(),
        generation: generation
    )
    let mode: CommandDragTap.Mode = options.command == "a2" ? .holdAndDecide : .rewrite
    let session = Session(options: options, generation: generation)
    let tap = CommandDragTap(
        mode: mode,
        generation: generation,
        snapshot: snapshot,
        onGesture: { session.record($0) },
        onClick: { session.recordClick($0) },
        onSkip: { session.recordSkip($0) }
    )
    session.start(
        mode: options.command,
        snapshot: snapshot,
        stop: {
            tap.stop()
            return tap.tapMaxUs
        },
        drain: { await tap.waitForReads() }
    )
    switch mode {
    case .rewrite:
        print("a1: while this runs, every drag that starts on an app item in the menu bar becomes a Command-drag, "
            + "and clicks on app items do not open their menus. It ends after \(options.seconds) seconds or "
            + "\(options.gestures) drags; Ctrl-C ends it now.")
    case .holdAndDecide:
        print("a2: while this runs, a press on an app item in the menu bar waits until you move or release it; "
            + "menus open on release. It ends after \(options.seconds) seconds or "
            + "\(options.gestures) drags and clicks; Ctrl-C ends it now.")
    }
    guard tap.start() else {
        FileHandle.standardError.write(Data("macOS refused the event tap.\n".utf8))
        exit(3)
    }

    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler {
        session.finish()
    }
    interrupt.resume()
    Task {
        try? await Task.sleep(for: .seconds(options.seconds))
        await session.finishAfterTimeLimit()
    }
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
    exit(0)
}

// MARK: - Start

setvbuf(stdout, nil, _IOLBF, 0)
let options = Options.parse(CommandLine.arguments)
switch options.command {
case "selftest":
    exit(runSelftest(options))
case "bar":
    requireAccessibility()
    exit(runBar(options))
default:
    requireAccessibility()
    runLive(options)
}
