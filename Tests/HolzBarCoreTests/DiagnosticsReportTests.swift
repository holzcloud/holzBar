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

    @Test("The report holds no path separators or quotes from a field")
    func noPathsFromFields() {
        var input = sample
        input.backend = "/Users/anna/Documents \"x\""
        let text = DiagnosticsReport.make(input)
        #expect(!text.contains("/"))
        #expect(!text.contains("\""))
    }
}
