import Testing
@testable import HolzBarCore

@Suite("DiagnosticsReport")
struct DiagnosticsReportTests {
    private var sample: DiagnosticsInput {
        DiagnosticsInput(
            appVersion: "0.0.8",
            appBuild: "42",
            macOSVersion: "26.7.1",
            macOSBuild: "25H123",
            modelIdentifier: "Mac15,6",
            architecture: "arm64",
            backend: "macOS 26",
            displayCount: 2,
            displaysWithNotch: 1,
            accessibilityGranted: true,
            screenRecordingGranted: false,
            launchesAtLogin: true,
            visibleItems: 5,
            hiddenItems: 12,
            alwaysHiddenItems: 3,
            profileCount: 2,
            groupCount: 1,
            spacerCount: 0,
            automationRuleCount: 4,
            snapshotCount: 9
        )
    }

    @Test("The report names the facts, in order")
    func report() {
        let text = DiagnosticsReport.make(sample)
        #expect(text.contains("holzBar: 0.0.8 (42)"))
        #expect(text.contains("macOS: 26.7.1 (25H123)"))
        #expect(text.contains("Mac: Mac15,6, arm64"))
        #expect(text.contains("Displays: 2, with a notch: 1"))
        #expect(text.contains("Accessibility: granted or on"))
        #expect(text.contains("Screen Recording: not granted or off"))
        #expect(text.contains("Items: 5 visible, 12 hidden, 3 always hidden"))
        #expect(text.contains("Automation rules: 4, snapshots: 9"))
        #expect(text.split(separator: "\n").count == 11)
    }

    @Test("A field keeps only version characters and a short length")
    func fieldCleaning() {
        #expect(DiagnosticsReport.field("/Users/anna/Library\nsecret|x") == "UsersannaLibrarysecretx")
        #expect(DiagnosticsReport.field(String(repeating: "a", count: 100)).count == DiagnosticsReport.maximumFieldLength)
        #expect(DiagnosticsReport.field("") == "unknown")
        #expect(DiagnosticsReport.field("\u{1B}[31m<>") == "31m")
    }

    @Test("A hostile field cannot add a line to the report")
    func noInjectedLines() {
        var input = sample
        input.modelIdentifier = "Mac15,6\nAccessibility: granted or on"
        let text = DiagnosticsReport.make(input)
        #expect(text.split(separator: "\n").count == 11)
    }

    @Test("Without an overflow state the report has no overflow line")
    func noOverflowLine() {
        let text = DiagnosticsReport.make(sample)
        #expect(text.split(separator: "\n").count == 11)
        #expect(!text.contains("overflow"))
    }

    @Test("The overflow state of macOS 27 is one last line")
    func overflowLine() {
        var input = sample
        input.nativeOverflow = "expanded"
        let lines = DiagnosticsReport.make(input).split(separator: "\n")
        #expect(lines.count == 12)
        #expect(lines.last == "macOS 27 overflow: expanded")
    }

    @Test("A hostile overflow state stays on one clean line")
    func hostileOverflowState() {
        var input = sample
        input.nativeOverflow = "expanded\n/Users/anna"
        let text = DiagnosticsReport.make(input)
        #expect(text.split(separator: "\n").count == 12)
        #expect(!text.contains("/"))
    }

    @Test("The report holds no path separators or quotes from a field")
    func noPathsFromFields() {
        var input = sample
        input.backend = "/Users/anna/Documents \"x\""
        let text = DiagnosticsReport.make(input)
        #expect(!text.contains("/"))
        #expect(!text.contains("\""))
    }

    @Test("Without an Apple Items state the report is as it was")
    func noAppleItemsLine() {
        let text = DiagnosticsReport.make(sample)
        #expect(text.split(separator: "\n").count == 11)
        #expect(!text.contains("Apple Items"))
    }

    @Test("The module being off is one last line")
    func appleItemsOff() {
        var input = sample
        input.appleItems = "off"
        let lines = DiagnosticsReport.make(input).split(separator: "\n")
        #expect(lines.count == 12)
        #expect(lines.last == "Apple Items: off")
    }

    @Test("The module being on names counts and words only, and the longest value is kept whole")
    func appleItemsOn() {
        var input = sample
        input.appleItems = "on, hidden 2, applied no, replaced 1"
        #expect(DiagnosticsReport.make(input).split(separator: "\n").last == "Apple Items: on, hidden 2, applied no, replaced 1")
        let longest = "on, hidden 4, applied yes, replaced 6"
        #expect(longest.count <= DiagnosticsReport.maximumFieldLength)
        input.appleItems = longest
        #expect(DiagnosticsReport.make(input).split(separator: "\n").last == "Apple Items: \(longest)")
    }

    @Test("The last drop is one line of fixed words, and none without a drop")
    func lastDrop() {
        var input = sample
        #expect(!DiagnosticsReport.make(input).contains("Last drop"))
        input.lastDrop = "macOS 27, shelf, hide, applied"
        #expect(DiagnosticsReport.make(input).split(separator: "\n").last == "Last drop: macOS 27, shelf, hide, applied")
        let longest = "macOS 27, outsideBar, refused, outside the bar, not applied"
        #expect(longest.count <= DiagnosticsReport.maximumLastDropLength)
        input.lastDrop = longest
        #expect(DiagnosticsReport.make(input).split(separator: "\n").last == "Last drop: \(longest)")
    }

    @Test("The last command-drag is one line of fixed words, after the last drop, and none without one")
    func lastCommandDrag() {
        var input = sample
        #expect(!DiagnosticsReport.make(input).contains("Last command-drag"))
        input.lastCommandDrag = "waited 1200 ms, 1 read, set hidden, applied"
        #expect(DiagnosticsReport.make(input).split(separator: "\n").last == "Last command-drag: waited 1200 ms, 1 read, set hidden, applied")
        input.lastDrop = "macOS 27, shelf, hide, applied"
        let lines = DiagnosticsReport.make(input).split(separator: "\n").map(String.init)
        #expect(lines.suffix(2) == ["Last drop: macOS 27, shelf, hide, applied", "Last command-drag: waited 1200 ms, 1 read, set hidden, applied"])
        let longest = CommandDragSection.summary(
            waitedMilliseconds: 99_999, reads: 99, decision: .ignore(.notAnAppItem), outcome: .nothing
        )
        #expect(longest.count <= DiagnosticsReport.maximumLastCommandDragLength)
        input.lastCommandDrag = longest
        #expect(DiagnosticsReport.make(input).contains("Last command-drag: \(longest)"))
    }

    @Test("A last command-drag with a newline or a home path is sanitised and limited")
    func lastCommandDragSanitised() {
        var input = sample
        input.lastCommandDrag = "waited 5 ms\n/Users/anna/Focus\nFake: line"
        let report = DiagnosticsReport.make(input)
        #expect(!report.contains("/Users/anna"))
        #expect(report.split(separator: "\n").filter { $0.hasPrefix("Fake:") }.isEmpty)
        input.lastCommandDrag = String(repeating: "a", count: 500)
        let line = DiagnosticsReport.make(input).split(separator: "\n").last.map(String.init) ?? ""
        #expect(line == "Last command-drag: " + String(repeating: "a", count: DiagnosticsReport.maximumLastCommandDragLength))
    }

    @Test("The Hiding line follows the last command-drag, or takes its place, and is absent while empty")
    func hiding() {
        var input = sample
        #expect(!DiagnosticsReport.make(input).contains("Hiding"))
        input.hiding = "anchor icon, icon put back 0"
        #expect(DiagnosticsReport.make(input).split(separator: "\n").last == "Hiding: anchor icon, icon put back 0")
        input.lastDrop = "macOS 27, shelf, hide, applied"
        #expect(DiagnosticsReport.make(input).split(separator: "\n").last == "Hiding: anchor icon, icon put back 0")
        input.lastCommandDrag = "waited 1200 ms, 1 read, set hidden, applied"
        input.lastShelfClick = "shown, clicked"
        let lines = DiagnosticsReport.make(input).split(separator: "\n").map(String.init)
        let index = lines.firstIndex { $0.hasPrefix("Last command-drag: ") }
        #expect(index.map { lines[$0 + 1] } == "Hiding: anchor icon, icon put back 0")
        #expect(lines.last == "Last Shelf click: shown, clicked")
    }

    @Test("The Hiding line is sanitised and limited")
    func hidingSanitised() {
        var input = sample
        input.hiding = "reveal all hidden\n/Users/anna/Focus\nFake: line"
        let report = DiagnosticsReport.make(input)
        #expect(!report.contains("/Users/anna"))
        #expect(report.split(separator: "\n").filter { $0.hasPrefix("Fake:") }.isEmpty)
        input.hiding = String(repeating: "a", count: 500)
        let line = DiagnosticsReport.make(input).split(separator: "\n").last.map(String.init) ?? ""
        #expect(line == "Hiding: " + String(repeating: "a", count: DiagnosticsReport.maximumHidingLength))
    }

    @Test("The macOS 27 hiding summary")
    func hidingSummary27() {
        let summary = DiagnosticsReport.hidingSummary27(
            reveal: "all hidden", agentRestarts: 0, lateAllowlist: 2, youngRetries: 1,
            forcedReads: 14, heldBack: 11, notchRechecks: 3
        )
        #expect(summary == "reveal all hidden, agent restarts 0, late allowlist 2, young retries 1, forced reads 14, held back 11, notch rechecks 3")
        let longest = DiagnosticsReport.hidingSummary27(
            reveal: "hidden revealed", agentRestarts: Int.max, lateAllowlist: Int.max, youngRetries: Int.max,
            forcedReads: Int.max, heldBack: Int.max, notchRechecks: Int.max
        )
        #expect(longest.count > DiagnosticsReport.maximumHidingLength)
        let usual = DiagnosticsReport.hidingSummary27(
            reveal: "hidden revealed", agentRestarts: 99_999, lateAllowlist: 99_999, youngRetries: 99_999,
            forcedReads: 99_999, heldBack: 99_999, notchRechecks: 99_999
        )
        #expect(usual.count <= DiagnosticsReport.maximumHidingLength)
    }

    @Test("The hiding summary before macOS 27")
    func hidingSummaryBefore27() {
        #expect(DiagnosticsReport.hidingSummaryBefore27(anchor: "icon", iconPutBack: 0) == "anchor icon, icon put back 0")
        #expect(DiagnosticsReport.hidingSummaryBefore27(anchor: "divider", iconPutBack: 2) == "anchor divider, icon put back 2")
    }

    @Test("A hiding summary holds lowercase letters, digits, spaces and commas only")
    func hidingSummaryCharacters() {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789 ,")
        let summaries = [
            DiagnosticsReport.hidingSummary27(
                reveal: "All\nHidden/../\u{7}", agentRestarts: -1, lateAllowlist: 2, youngRetries: 3,
                forcedReads: 4, heldBack: 5, notchRechecks: 6
            ),
            DiagnosticsReport.hidingSummaryBefore27(anchor: "Icon\r\n\t:x", iconPutBack: -3),
        ]
        for summary in summaries {
            #expect(summary.allSatisfy { allowed.contains($0) })
        }
        #expect(summaries[1] == "anchor iconx, icon put back 0")
    }

    @Test("The last Shelf click is one line of fixed words, and none before a click")
    func lastShelfClick() {
        var input = sample
        #expect(!DiagnosticsReport.make(input).contains("Last Shelf click"))
        input.lastShelfClick = "failed, not shown and not reachable"
        #expect(DiagnosticsReport.make(input).contains("Last Shelf click: failed, not shown and not reachable"))
        input.lastShelfClick = "press refused\n/Users/anna/x"
        #expect(!DiagnosticsReport.make(input).contains("/Users/anna"))
    }

    @Test("A last drop with a newline or a home path is sanitised like every field")
    func lastDropSanitised() {
        var input = sample
        input.lastDrop = "macOS 27, shelf\n/Users/anna/Focus\nFake: line"
        let report = DiagnosticsReport.make(input)
        #expect(!report.contains("/Users/anna"))
        #expect(report.split(separator: "\n").filter { $0.hasPrefix("Fake:") }.isEmpty)
    }

    @Test("The Apple Items line comes after the overflow line")
    func appleItemsAfterOverflow() {
        var input = sample
        input.nativeOverflow = "collapsed"
        input.appleItems = "off"
        let lines = DiagnosticsReport.make(input).split(separator: "\n")
        #expect(lines.count == 13)
        #expect(lines[11] == "macOS 27 overflow: collapsed")
        #expect(lines[12] == "Apple Items: off")
    }

    @Test("A hostile Apple Items field stays on one clean line without a path or a name")
    func hostileAppleItems() {
        var input = sample
        input.appleItems = "on, hidden 1\n/Users/anna/Focus \"x\"\nFake: line"
        let text = DiagnosticsReport.make(input)
        #expect(text.split(separator: "\n").count == 12)
        #expect(!text.contains("/"))
        #expect(!text.contains("\""))
    }

    @Test("With no Shelf field the report is as before")
    func shelfAbsent() {
        let text = DiagnosticsReport.make(sample)
        #expect(!text.contains("Shelf"))
        #expect(text.split(separator: "\n").count == 11)
    }

    @Test("The Shelf's style and location are one last line in fixed words")
    func shelfLine() {
        for words in ["attached, dynamic", "floating, screen edge", "floating, mouse pointer"] {
            var input = sample
            input.shelf = words
            let lines = DiagnosticsReport.make(input).split(separator: "\n")
            #expect(lines.count == 12)
            #expect(lines.last == "Shelf: \(words)")
        }
    }

    @Test("The Shelf line comes after the Apple Items line")
    func shelfAfterAppleItems() {
        var input = sample
        input.appleItems = "off"
        input.shelf = "attached, holzBar icon"
        let lines = DiagnosticsReport.make(input).split(separator: "\n")
        #expect(lines.count == 13)
        #expect(lines[11] == "Apple Items: off")
        #expect(lines[12] == "Shelf: attached, holzBar icon")
    }

    @Test("A hostile Shelf field stays on one clean line without a path")
    func hostileShelf() {
        var input = sample
        input.shelf = "floating\n/Users/anna/Focus \"x\"\nFake: line"
        let text = DiagnosticsReport.make(input)
        #expect(text.split(separator: "\n").count == 12)
        #expect(!text.contains("/"))
        #expect(!text.contains("\""))
    }

    @Test("With no accessory battery field the report is as before")
    func accessoryBatteryAbsent() {
        let text = DiagnosticsReport.make(sample)
        #expect(!text.contains("Accessory battery"))
        #expect(text.split(separator: "\n").count == 11)
    }

    @Test("The accessory battery state is one last line in fixed words")
    func accessoryBatteryLine() {
        for word in ["available", "not available", "off"] {
            var input = sample
            input.accessoryBattery = word
            let lines = DiagnosticsReport.make(input).split(separator: "\n")
            #expect(lines.count == 12)
            #expect(lines.last == "Accessory battery: \(word)")
        }
    }

    @Test("A hostile accessory battery field stays on one clean line without a path or a name")
    func hostileAccessoryBattery() {
        var input = sample
        input.accessoryBattery = "available\n/Users/anna/Annas AirPods \"x\"\nFake: line"
        let text = DiagnosticsReport.make(input)
        #expect(text.split(separator: "\n").count == 12)
        #expect(!text.contains("/"))
        #expect(!text.contains("\""))
    }
}
