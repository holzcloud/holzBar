import Foundation
import Testing
@testable import HolzBarCore

@Suite("ScriptLaunch")
struct ScriptLaunchTests {
    private let folder = "/Users/u/Scripts"
    private let home = "/Users/u"

    private func plan(
        name: String = "backup.sh",
        kind: ScriptKind = .executable,
        folder: String? = nil,
        event: ScriptEvent = .ruleStarted
    ) -> ScriptLaunchPlan? {
        ScriptLaunchPlan.make(
            fileName: name,
            kind: kind,
            folderPath: folder ?? self.folder,
            homePath: home,
            event: event
        )
    }

    @Test("There are exactly five events, with fixed names")
    func eventNames() {
        #expect(ScriptEvent.allCases.count == 5)
        #expect(ScriptEvent.ruleStarted.rawValue == "rule-started")
        #expect(ScriptEvent.ruleEnded.rawValue == "rule-ended")
        #expect(ScriptEvent.check.rawValue == "check")
        #expect(ScriptEvent.profileWillApply.rawValue == "profile-will-apply")
        #expect(ScriptEvent.profileDidApply.rawValue == "profile-did-apply")
    }

    @Test("An executable runs itself with no arguments, in the folder, with four environment names")
    func executablePlan() {
        let expected = ScriptLaunchPlan(
            executablePath: "/Users/u/Scripts/backup.sh",
            arguments: [],
            environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME": "/Users/u",
                "LANG": "en_US.UTF-8",
                "HOLZBAR_EVENT": "rule-started",
            ],
            workingDirectoryPath: "/Users/u/Scripts"
        )
        #expect(plan() == expected)
    }

    @Test("An AppleScript runs through osascript with only its own path")
    func appleScriptPlan() {
        let result = plan(name: "check.scpt", kind: .appleScript, event: .check)
        #expect(result?.executablePath == "/usr/bin/osascript")
        #expect(result?.arguments == ["/Users/u/Scripts/check.scpt"])
        #expect(result?.workingDirectoryPath == "/Users/u/Scripts")
        #expect(result?.environment["HOLZBAR_EVENT"] == "check")
        #expect(result?.environment.count == 4)
    }

    @Test("A trailing slash on the folder changes nothing")
    func trailingSlash() {
        #expect(plan(folder: "/Users/u/Scripts/") == plan())
    }

    @Test("A name that is not plain, or a folder that is not absolute, gives no plan")
    func refusedInput() {
        #expect(plan(name: "") == nil)
        #expect(plan(name: "../x.sh") == nil)
        #expect(plan(name: ".hidden") == nil)
        #expect(plan(name: "a/b.sh") == nil)
        #expect(plan(folder: "Scripts") == nil)
        #expect(plan(folder: "") == nil)
    }

    @Test("Every event gives exactly four environment names and the event as its value")
    func environmentForEveryEvent() {
        for event in ScriptEvent.allCases {
            for kind in [ScriptKind.executable, .appleScript] {
                let environment = plan(kind: kind, event: event)?.environment
                #expect(environment?.keys.sorted() == ["HOLZBAR_EVENT", "HOME", "LANG", "PATH"])
                #expect(environment?["HOLZBAR_EVENT"] == event.rawValue)
                #expect(environment?["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
            }
        }
    }

    @Test("The time limit defaults to 10 seconds and stays between 1 and 60")
    func timeLimits() {
        #expect(ScriptLimits.timeLimit(nil) == 10)
        #expect(ScriptLimits.timeLimit(0) == 1)
        #expect(ScriptLimits.timeLimit(-5) == 1)
        #expect(ScriptLimits.timeLimit(1) == 1)
        #expect(ScriptLimits.timeLimit(30) == 30)
        #expect(ScriptLimits.timeLimit(60) == 60)
        #expect(ScriptLimits.timeLimit(61) == 60)
        #expect(ScriptLimits.timeLimit(Int.max) == 60)
        #expect(ScriptLimits.killGraceSeconds == 2)
        #expect(ScriptLimits.maximumOutputBytes == 65_536)
    }

    @Test("Only a clean exit is success")
    func terminationSuccess() {
        #expect(ScriptTermination.exited(0).succeeded)
        #expect(!ScriptTermination.exited(1).succeeded)
        #expect(!ScriptTermination.signaled(15).succeeded)
        #expect(!ScriptTermination.timedOut.succeeded)
        #expect(!ScriptTermination.notLaunched.succeeded)
        #expect(!ScriptTermination.skipped(.busy).succeeded)
        #expect(!ScriptTermination.skipped(.rateLimited).succeeded)
        #expect(ScriptTermination.skipped(.busy) != .skipped(.rateLimited))
    }
}
