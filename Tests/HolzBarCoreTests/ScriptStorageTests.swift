import Foundation
import Testing
@testable import HolzBarCore

@Suite("ScriptStorage")
struct ScriptStorageTests {
    private let goodHash = String(repeating: "ab", count: 32)
    private let otherHash = String(repeating: "0f", count: 32)

    private func plain(_ name: String) -> AutomationRule {
        AutomationRule(
            name: name,
            clauses: [AutomationClause(condition: .power(.battery))],
            action: .showSection(.hidden)
        )
    }

    private func running(_ script: String, name: String = "Backup", restores: Bool = true) -> AutomationRule {
        AutomationRule(
            name: name,
            clauses: [AutomationClause(condition: .power(.battery))],
            action: .runScript(script),
            restoresWhenEnded: restores
        )
    }

    private func asking(_ script: String, name: String = "Asks") -> AutomationRule {
        AutomationRule(
            name: name,
            clauses: [AutomationClause(condition: .scriptSucceeds(script))],
            action: .showSection(.hidden)
        )
    }

    private func hook(
        _ profile: String?,
        _ timing: ProfileHookTiming,
        _ script: String = "hook.sh"
    ) -> ProfileHook {
        ProfileHook(profileName: profile, timing: timing, scriptName: script)
    }

    private func encoded(_ file: ScriptStoreFile) throws -> Data {
        try #require(file.encoded())
    }

    // MARK: Format

    @Test("A file round-trips through JSON")
    func roundTrip() throws {
        var file = ScriptStoreFile()
        file.folderPath = "/Users/me/Scripts"
        file.approvals = ["a.sh": goodHash]
        file.timeLimits = ["a.sh": 30]
        file.rules = [running("a.sh")]
        file.ruleOrder = file.rules.map(\.id)
        file.profileHooks = [hook("Work", .beforeApplying), hook(nil, .afterApplying, "b.sh")]
        file.hasMigratedLegacyData = true
        let decoded = ScriptStoreFile.decode(try encoded(file))
        #expect(decoded == .file(file))
    }

    @Test("A newer version is not read, data that is not a store is unreadable")
    func decodeRefusals() {
        #expect(ScriptStoreFile.decode(Data(#"{"version":2}"#.utf8)) == .unsupportedVersion)
        #expect(ScriptStoreFile.decode(Data("nonsense".utf8)) == .unreadable)
        #expect(ScriptStoreFile.decode(Data(#"{"approvals":{}}"#.utf8)) == .unreadable)
        let tooLarge = Data(repeating: 0x20, count: ScriptStoreFile.maximumSize + 1)
        #expect(ScriptStoreFile.decode(tooLarge) == .unreadable)
    }

    @Test("A version 1 file with keys missing decodes with their defaults")
    func missingKeys() {
        #expect(ScriptStoreFile.decode(Data(#"{"version":1}"#.utf8)) == .file(ScriptStoreFile()))
        let partial = ScriptStoreFile.decode(Data(#"{"version":1,"hasMigratedLegacyData":true,"future":42}"#.utf8))
        guard case .file(let file) = partial else {
            Issue.record("A partial version 1 file must decode")
            return
        }
        #expect(file.hasMigratedLegacyData)
        #expect(file.folderPath == nil)
        #expect(file.approvals.isEmpty)
        #expect(file.profileHooks.isEmpty)
    }

    // MARK: Validation

    @Test("Approvals need a plain name and a full lowercase SHA-256")
    func approvalsAreValidated() {
        var file = ScriptStoreFile()
        file.approvals = [
            "ok.sh": goodHash,
            "../x.sh": goodHash,
            ".hidden.sh": goodHash,
            "short.sh": "abcd",
            "upper.sh": String(repeating: "AB", count: 32),
            "long.sh": goodHash + "00",
            "prefix.sh": String(repeating: "g", count: 64),
        ]
        #expect(file.validated().approvals == ["ok.sh": goodHash])
        #expect(ScriptStoreFile.isValidHash(goodHash))
        #expect(!ScriptStoreFile.isValidHash(""))
    }

    @Test("Time limits are clamped to 1 through 60 and need a plain name")
    func timeLimitsAreValidated() {
        var file = ScriptStoreFile()
        file.timeLimits = ["a.sh": 0, "b.sh": 500, "c.sh": 30, "../d.sh": 5]
        #expect(file.validated().timeLimits == ["a.sh": 1, "b.sh": 60, "c.sh": 30])
    }

    @Test("Only valid rules that use a script are kept, once each")
    func rulesAreValidated() {
        let script = running("a.sh")
        let broken = running("b.sh", name: "")
        var file = ScriptStoreFile()
        file.rules = [plain("Plain"), script, script, broken, asking("c.sh")]
        let rules = file.validated().rules
        #expect(rules.map(\.name) == ["Backup", "Asks"])
    }

    @Test("Rules are capped at the rule limit")
    func rulesAreCapped() {
        var file = ScriptStoreFile()
        file.rules = (0..<(AutomationRule.maximumCount + 5)).map { running("a.sh", name: "Rule \($0)") }
        #expect(file.validated().rules.count == AutomationRule.maximumCount)
    }

    @Test("Hooks need a plain script name and a sensible profile name")
    func hooksAreValidated() {
        var file = ScriptStoreFile()
        file.profileHooks = [
            hook("Work", .beforeApplying),
            hook(nil, .afterApplying),
            hook("Work", .beforeApplying, "../evil.sh"),
            hook("", .beforeApplying),
            hook(String(repeating: "x", count: 81), .beforeApplying),
            hook("Work", .afterApplying, ""),
        ]
        let hooks = file.validated().profileHooks
        #expect(hooks.count == 2)
        #expect(hooks.allSatisfy { $0.isValid })
    }

    @Test("Lists are capped and a repeated id is kept once")
    func listsAreCapped() {
        var file = ScriptStoreFile()
        file.approvals = Dictionary(
            uniqueKeysWithValues: (0..<(ScriptStoreFile.maximumEntries + 20)).map { ("s\($0).sh", goodHash) }
        )
        file.timeLimits = Dictionary(
            uniqueKeysWithValues: (0..<(ScriptStoreFile.maximumEntries + 20)).map { ("s\($0).sh", 5) }
        )
        file.profileHooks = (0..<(ProfileHooks.maximumCount + 10)).map { hook("P\($0)", .beforeApplying) }
        let repeated = UUID()
        file.ruleOrder = [repeated, UUID(), repeated, repeated]
        let result = file.validated()
        #expect(result.approvals.count == ScriptStoreFile.maximumEntries)
        #expect(result.timeLimits.count == ScriptStoreFile.maximumEntries)
        #expect(result.profileHooks.count == ProfileHooks.maximumCount)
        #expect(result.ruleOrder.count == 2)
        #expect(result.ruleOrder.first == repeated)
    }

    @Test("A folder path must be absolute")
    func folderPathIsValidated() {
        var file = ScriptStoreFile()
        file.folderPath = "relative/folder"
        #expect(file.validated().folderPath == nil)
        file.folderPath = ""
        #expect(file.validated().folderPath == nil)
        file.folderPath = "/Users/me/Scripts"
        #expect(file.validated().folderPath == "/Users/me/Scripts")
    }

    // MARK: Split and merge

    @Test("Rules that use a script go to the Mac's own file, in their order")
    func split() {
        let plain1 = plain("One")
        let script = running("a.sh")
        let plain2 = plain("Two")
        let parts = AutomationRuleStorage.split([plain1, script, plain2])
        #expect(parts.settings == [plain1, plain2])
        #expect(parts.local == [script])
        #expect(parts.order == [plain1.id, script.id, plain2.id])
    }

    @Test("Merging puts the rules back in their order")
    func merge() {
        let plain1 = plain("One")
        let script = running("a.sh")
        let plain2 = plain("Two")
        let merged = AutomationRuleStorage.merge(
            settings: [plain1, plain2],
            local: [script],
            order: [plain1.id, script.id, plain2.id]
        )
        #expect(merged == [plain1, script, plain2])
    }

    @Test("A script rule in the settings is left out and counted")
    func mergeLeavesOutScriptRulesOfTheSettings() {
        let plain1 = plain("One")
        let imported = running("evil.sh", name: "Imported")
        let own = asking("mine.sh")
        let merged = AutomationRuleStorage.merge(settings: [plain1, imported], local: [own], order: [])
        #expect(merged == [plain1, own])
        #expect(AutomationRuleStorage.droppedScriptRuleCount(settings: [plain1, imported, asking("x.sh")]) == 2)
        #expect(AutomationRuleStorage.droppedScriptRuleCount(settings: [plain1]) == 0)
    }

    @Test("Rules missing from the order follow the ordered ones; a repeated id is kept once")
    func mergeOrder() {
        let first = plain("First")
        let second = plain("Second")
        let script = running("a.sh")
        let third = plain("Third")
        let merged = AutomationRuleStorage.merge(
            settings: [first, second, third],
            local: [script],
            order: [third.id, UUID(), third.id]
        )
        #expect(merged.map(\.name) == ["Third", "First", "Second", "Backup"])
        let twice = AutomationRuleStorage.merge(settings: [first, first], local: [], order: [])
        #expect(twice == [first])
    }

    // MARK: Migration of the betas' data

    @Test("The betas' script rules and approvals move once into the store")
    func adoptingLegacy() {
        let runs = running("a.sh", restores: true)
        let asks = asking("b.sh")
        let migrated = ScriptStoreFile().adoptingLegacy(
            rules: [runs, asks],
            approvals: ["a.sh": goodHash, "../x": goodHash, "b.sh": "short"]
        )
        #expect(migrated.hasMigratedLegacyData)
        #expect(migrated.approvals == ["a.sh": goodHash])
        #expect(migrated.rules.map(\.id) == [runs.id, asks.id])
        #expect(migrated.rules.first?.restoresWhenEnded == false)
        #expect(migrated.rules.last?.restoresWhenEnded == asks.restoresWhenEnded)
    }

    @Test("A file that already migrated comes back unchanged")
    func adoptingLegacyOnlyOnce() {
        var file = ScriptStoreFile()
        file.hasMigratedLegacyData = true
        file.approvals = ["keep.sh": otherHash]
        let result = file.adoptingLegacy(rules: [running("a.sh")], approvals: ["a.sh": goodHash])
        #expect(result == file)
    }

    @Test("The migration keeps what the store already holds and takes the order of the settings")
    func adoptingLegacyKeepsExisting() {
        var file = ScriptStoreFile()
        file.approvals = ["a.sh": otherHash]
        let legacy = running("a.sh")
        let order = [UUID(), legacy.id]
        let result = file.adoptingLegacy(rules: [legacy], approvals: ["a.sh": goodHash, "b.sh": goodHash], order: order)
        #expect(result.approvals == ["a.sh": otherHash, "b.sh": goodHash])
        #expect(result.ruleOrder == order)
    }

    @Test("An approval binds the full hash, not its first characters")
    func fullHashIsBound() {
        let sibling = String(goodHash.prefix(8)) + String(repeating: "0", count: 56)
        let info = ScriptFileInfo(
            name: "a.sh",
            isRegularFile: true,
            isSymbolicLink: false,
            isOwnedByCurrentUser: true,
            mode: 0o755,
            hasQuarantineAttribute: false,
            size: 10,
            sha256: sibling
        )
        #expect(ScriptStoreFile.isValidHash(sibling))
        #expect(ScriptGate.decide(info, approvedHash: goodHash) == .needsApproval)
        #expect(ScriptGate.decide(info, approvedHash: sibling) == .allowed(.executable))
    }

    // MARK: Profile hooks

    @Test("A profile's before hooks come first, then those for every profile")
    func hookNames() {
        let hooks = [
            hook(nil, .beforeApplying, "all.sh"),
            hook("Work", .beforeApplying, "work.sh"),
            hook("Work", .afterApplying, "after.sh"),
            hook("Home", .beforeApplying, "home.sh"),
            hook("Work", .beforeApplying, "all.sh"),
            hook(nil, .afterApplying, "everyone-after.sh"),
        ]
        #expect(ProfileHooks.scriptNames(for: "Work", timing: .beforeApplying, in: hooks) == ["work.sh", "all.sh"])
        #expect(ProfileHooks.scriptNames(for: "Work", timing: .afterApplying, in: hooks) == ["after.sh", "everyone-after.sh"])
        #expect(ProfileHooks.scriptNames(for: "Other", timing: .beforeApplying, in: hooks) == ["all.sh"])
        #expect(ProfileHooks.scriptNames(for: "Work", timing: .beforeApplying, in: []).isEmpty)
    }

    @Test("Hooks follow a renamed profile and go with a deleted one")
    func hooksFollowTheProfile() {
        let hooks = [
            hook("Work", .beforeApplying, "work.sh"),
            hook("Home", .afterApplying, "home.sh"),
            hook(nil, .afterApplying, "all.sh"),
        ]
        let renamed = ProfileHooks.renaming(hooks, from: "Work", to: "Office")
        #expect(renamed.map(\.profileName) == ["Office", "Home", nil])
        #expect(renamed.map(\.id) == hooks.map(\.id))
        let removed = ProfileHooks.removing(hooks, profileName: "Work")
        #expect(removed.map(\.scriptName) == ["home.sh", "all.sh"])
    }

    @Test("Each timing has its own event")
    func timingEvents() {
        #expect(ProfileHookTiming.beforeApplying.event == .profileWillApply)
        #expect(ProfileHookTiming.afterApplying.event == .profileDidApply)
    }
}
