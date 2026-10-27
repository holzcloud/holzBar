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
}
