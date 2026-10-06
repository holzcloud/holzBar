import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSyncPolicy")
struct SettingsSyncPolicyTests {
    private let thisMac = "this"
    private let base = "base"
    private let changed = "changed"
    private let lastSynced = Date(timeIntervalSince1970: 1_000_000)

    private func local(
        _ userDigest: String,
        base: String?,
        pending: Date? = nil,
        postponed: Date? = nil,
        forcesWrite: Bool = false,
        keepsOver: Date? = nil
    ) -> SettingsSyncPolicy.Local {
        var local = SettingsSyncPolicy.Local(
            userDigest: userDigest,
            base: base,
            pending: pending,
            postponed: postponed,
            forcesWrite: forcesWrite
        )
        local.keepsOver = keepsOver
        return local
    }

    private func version(
        _ userDigest: String,
        fromThisMac: Bool = false,
        isNewer: Bool = true,
        modified: Date? = nil
    ) -> SettingsSyncPolicy.File {
        .version(
            SettingsSyncPolicy.Version(
                isFromThisMac: fromThisMac,
                modified: modified ?? lastSynced.addingTimeInterval(60),
                isNewer: isNewer,
                userDigest: userDigest
            )
        )
    }

    // MARK: Joining

    @Test("Joining an empty folder writes this Mac's settings")
    func joinWithoutFile() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(base, base: nil), file: .missing) == .write)
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(base, base: nil), file: .unusable) == .write)
    }

    @Test("Joining a folder with this Mac's own, different file writes")
    func joinOwnFile() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: nil), file: version(base, fromThisMac: true)) == .write)
    }

    @Test("Joining a folder with equal settings only adopts them")
    func joinEqualFile() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(base, base: nil), file: version(base)) == .adopt)
    }

    @Test("Joining a folder with another Mac's different settings asks")
    func joinDifferentFile() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: nil), file: version(base)) == .ask)
        // Also when the file is not newer, as for a Mac whose settings were copied.
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: nil), file: version(base, isNewer: false)) == .ask)
        #expect(SettingsSyncPolicy.decide(.check, local: local(changed, base: nil), file: version(base)) == .ask)
    }

    @Test("Joining a folder whose file cannot be read tries again later")
    func joinUnreadable() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(base, base: nil), file: .unreadable) == .retry)
    }

    // MARK: Running

    @Test("A newer version from another Mac without local changes is applied")
    func newerWithoutChanges() {
        #expect(SettingsSyncPolicy.decide(.check, local: local(base, base: base), file: version(changed)) == .apply)
        #expect(SettingsSyncPolicy.decide(.launch, local: local(base, base: base), file: version(changed)) == .apply)
    }

    @Test("A newer version from another Mac with local changes asks")
    func newerWithChanges() {
        #expect(SettingsSyncPolicy.decide(.check, local: local(changed, base: base), file: version("other")) == .ask)
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: base), file: version("other")) == .ask)
        #expect(SettingsSyncPolicy.decide(.launch, local: local(changed, base: base), file: version("other")) == .ask)
    }

    @Test("A newer version with this Mac's user settings is adopted")
    func newerWithEqualSettings() {
        #expect(SettingsSyncPolicy.decide(.check, local: local(changed, base: base), file: version(changed)) == .adopt)
        #expect(SettingsSyncPolicy.decide(.launch, local: local(base, base: base), file: version(base)) == .adopt)
    }

    @Test("A version the user postponed is not asked about again in the session")
    func postponedVersion() {
        let modified = lastSynced.addingTimeInterval(60)
        let postponed = local(changed, base: base, pending: modified, postponed: modified)
        #expect(SettingsSyncPolicy.decide(.check, local: postponed, file: version("other", modified: modified)) == .wait)
        // A newer version asks or applies again.
        let newer = lastSynced.addingTimeInterval(120)
        #expect(SettingsSyncPolicy.decide(.check, local: postponed, file: version("other", modified: newer)) == .ask)
        let unchanged = local(base, base: base, pending: modified, postponed: modified)
        #expect(SettingsSyncPolicy.decide(.check, local: unchanged, file: version("other", modified: newer)) == .apply)
        // The next launch asks again.
        #expect(SettingsSyncPolicy.decide(.launch, local: postponed, file: version("other", modified: modified)) == .ask)
    }

    @Test("This Mac's own file is written over only with local changes")
    func ownFile() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: base), file: version(base, fromThisMac: true)) == .write)
        #expect(SettingsSyncPolicy.decide(.check, local: local(base, base: base), file: version("other", fromThisMac: true)) == .none)
    }

    @Test("A version that is not newer is written over only with local changes")
    func notNewer() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: base), file: version(base, isNewer: false)) == .write)
        // A file dated far in the future is not newer either.
        let future = Date.now.addingTimeInterval(24 * 60 * 60)
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: base), file: version(base, isNewer: false, modified: future)) == .write)
        #expect(SettingsSyncPolicy.decide(.check, local: local(base, base: base), file: version(changed, isNewer: false)) == .none)
    }

    @Test("A missing file is written only with local changes")
    func missingFile() {
        #expect(SettingsSyncPolicy.decide(.localChange, local: local(changed, base: base), file: .missing) == .write)
        #expect(SettingsSyncPolicy.decide(.check, local: local(base, base: base), file: .missing) == .none)
    }

    @Test("The launch never writes")
    func launchNeverWrites() {
        #expect(SettingsSyncPolicy.decide(.launch, local: local(changed, base: base), file: .missing) == .none)
        #expect(SettingsSyncPolicy.decide(.launch, local: local(changed, base: nil), file: .missing) == .none)
        #expect(SettingsSyncPolicy.decide(.launch, local: local(changed, base: base), file: version(base, fromThisMac: true)) == .none)
        #expect(SettingsSyncPolicy.decide(.launch, local: local(changed, base: base), file: version(base, isNewer: false)) == .none)
    }

    @Test("Keeping this Mac's settings writes over the version the user answered")
    func keepThisMac() {
        let answered = lastSynced.addingTimeInterval(60)
        let forced = local(changed, base: base, pending: answered, forcesWrite: true, keepsOver: answered)
        #expect(SettingsSyncPolicy.decide(.localChange, local: forced, file: version("other")) == .write)
        #expect(SettingsSyncPolicy.decide(.localChange, local: forced, file: version(changed)) == .adopt)
        #expect(SettingsSyncPolicy.decide(.localChange, local: forced, file: .unreadable) == .retry)
        #expect(SettingsSyncPolicy.decide(.localChange, local: forced, file: .missing) == .write)
        #expect(SettingsSyncPolicy.decide(.launch, local: forced, file: version("other")) == .none)
        // An older version, and this Mac's own, are written over too.
        #expect(SettingsSyncPolicy.decide(.localChange, local: forced, file: version("older", modified: lastSynced.addingTimeInterval(30))) == .write)
        #expect(SettingsSyncPolicy.decide(.localChange, local: forced, file: version("own", fromThisMac: true, modified: answered.addingTimeInterval(60))) == .write)
        let joining = local(changed, base: nil, forcesWrite: true, keepsOver: answered)
        #expect(SettingsSyncPolicy.decide(.localChange, local: joining, file: version("other")) == .write)
    }

    @Test("Keeping this Mac's settings never writes over a version that arrived while the question was open")
    func keepThisMacSparesLaterVersion() {
        let answered = lastSynced.addingTimeInterval(60)
        let later = version("later", modified: answered.addingTimeInterval(1))
        // This Mac changed its settings, so the later version is asked about.
        let forced = local(changed, base: base, pending: answered, forcesWrite: true, keepsOver: answered)
        #expect(SettingsSyncPolicy.decide(.localChange, local: forced, file: later) == .ask)
        // Without a change of this Mac's, it is applied like any newer version.
        let unchanged = local(base, base: base, pending: answered, forcesWrite: true, keepsOver: answered)
        #expect(SettingsSyncPolicy.decide(.localChange, local: unchanged, file: later) == .apply)
        // A joining Mac asks.
        let joining = local(changed, base: nil, forcesWrite: true, keepsOver: answered)
        #expect(SettingsSyncPolicy.decide(.localChange, local: joining, file: later) == .ask)
        // A keep without an answered version writes over no other Mac's version.
        let unanswered = local(changed, base: base, forcesWrite: true)
        #expect(SettingsSyncPolicy.decide(.localChange, local: unanswered, file: version("other")) == .ask)
        #expect(SettingsSyncPolicy.keepsThisMac(over: SettingsSyncPolicy.Version(isFromThisMac: true, modified: answered, isNewer: false, userDigest: "own"), local: unanswered))
        // Without a keep, nothing is written over.
        #expect(!SettingsSyncPolicy.keepsThisMac(over: SettingsSyncPolicy.Version(isFromThisMac: true, modified: answered, isNewer: false, userDigest: "own"), local: local(changed, base: base, keepsOver: answered)))
    }

    // MARK: Exchanges

    @Test("A pending version pauses pushes")
    func pendingBlocksPush() {
        let pending = local(changed, base: base, pending: lastSynced)
        #expect(!SettingsSyncPolicy.needsExchange(.localChange, local: pending))
        #expect(SettingsSyncPolicy.needsExchange(.check, local: pending))
        var forced = pending
        forced.forcesWrite = true
        #expect(SettingsSyncPolicy.needsExchange(.localChange, local: forced))
    }

    @Test("Unchanged settings are not pushed, and the file is not read")
    func unchangedNotPushed() {
        #expect(!SettingsSyncPolicy.needsExchange(.localChange, local: local(base, base: base)))
        #expect(SettingsSyncPolicy.needsExchange(.localChange, local: local(changed, base: base)))
        #expect(SettingsSyncPolicy.needsExchange(.localChange, local: local(base, base: nil)))
        #expect(SettingsSyncPolicy.needsExchange(.check, local: local(base, base: base)))
        #expect(SettingsSyncPolicy.needsExchange(.launch, local: local(base, base: base)))
    }

    // MARK: Hints

    @Test("A waiting version offers a restart, or a choice when this Mac changed or joins")
    func hints() {
        #expect(SettingsSyncPolicy.hint(for: local(base, base: base)) == .restart)
        #expect(SettingsSyncPolicy.hint(for: local(changed, base: base)) == .choice(isJoining: false))
        #expect(SettingsSyncPolicy.hint(for: local(changed, base: nil)) == .choice(isJoining: true))
        #expect(SettingsSyncPolicy.hint(for: local(base, base: nil)) == .choice(isJoining: true))
    }

    @Test("The hint offers a restart exactly where a newer version is applied, and a choice where it asks")
    func hintMatchesDecision() {
        let candidates = [local(base, base: base), local(changed, base: base), local(changed, base: nil), local(base, base: nil)]
        for candidate in candidates {
            let action = SettingsSyncPolicy.decide(.check, local: candidate, file: version("other"))
            let hint = SettingsSyncPolicy.hint(for: candidate)
            #expect((action == .apply) == (hint == .restart))
            #expect((action == .ask) == (hint != .restart))
        }
    }

    @Test("A change on this Mac turns a waiting restart into a choice")
    func localChangeTurnsRestartIntoChoice() {
        let pending = lastSynced.addingTimeInterval(60)
        #expect(SettingsSyncPolicy.hint(for: local(base, base: base, pending: pending)) == .restart)
        #expect(SettingsSyncPolicy.hint(for: local(changed, base: base, pending: pending)) == .choice(isJoining: false))
    }

    // MARK: Learned keys

    @Test("Learned keys never make settings differ")
    func learnedKeysNeverDiffer() {
        let local: [String: Any] = ["ShowOnHover": true, "KnownItemTags": ["a"], "MacOS27LayoutSeeded": false]
        let remote: [String: Any] = ["ShowOnHover": true, "KnownItemTags": ["a", "b"], "MacOS27LayoutSeeded": true]
        #expect(SettingsSyncPolicy.userDigest(of: local) == SettingsSyncPolicy.userDigest(of: remote))
        let file = version(SettingsSyncPolicy.userDigest(of: remote))
        let mac = self.local(SettingsSyncPolicy.userDigest(of: local), base: base)
        #expect(SettingsSyncPolicy.decide(.check, local: mac, file: file) == .adopt)
    }

    @Test("Learned arrays are united and flags combined with OR")
    func learnedMerge() {
        let local: [String: Any] = ["KnownItemTags": ["b", "a"], "MacOS27LayoutSeeded": false, "hasMigrated0_8_0": true]
        let remote: [String: Any] = [
            "KnownItemTags": ["c", "a"],
            "KnownApplications27": ["x"],
            "MacOS27LayoutSeeded": true,
            "hasMigrated0_8_0": false,
            "ShowOnHover": true,
        ]
        let merged = SettingsSyncPolicy.learnedSettings(merging: remote, into: local)
        #expect(merged["KnownItemTags"] as? [String] == ["a", "b", "c"])
        #expect(merged["KnownApplications27"] as? [String] == ["x"])
        #expect(merged["MacOS27LayoutSeeded"] as? Bool == true)
        #expect(merged["hasMigrated0_8_0"] == nil)
        #expect(merged["ShowOnHover"] == nil)
    }

    @Test("Nothing is merged when this Mac already knows everything")
    func learnedMergeEmpty() {
        let local: [String: Any] = ["KnownItemTags": ["a", "b"], "MacOS27LayoutSeeded": true]
        let remote: [String: Any] = ["KnownItemTags": ["b"], "MacOS27LayoutSeeded": false, "TitleChangingItemOwners": 3]
        #expect(SettingsSyncPolicy.learnedSettings(merging: remote, into: local).isEmpty)
    }

    @Test("Applying keeps the remote user settings and merges the learned ones")
    func settingsToApply() {
        let local: [String: Any] = ["KnownItemTags": ["a"], "MacOS27Layout": ["x": 1], "ShowOnHover": false]
        let remote: [String: Any] = ["KnownItemTags": ["b"], "ShowOnHover": true, "UseIceBar": true]
        let applied = SettingsSyncPolicy.settingsToApply(remote, over: local)
        #expect(Set(applied.keys) == ["KnownItemTags", "ShowOnHover", "UseIceBar"])
        #expect(applied["KnownItemTags"] as? [String] == ["a", "b"])
        #expect(applied["ShowOnHover"] as? Bool == true)
        #expect(applied["MacOS27Layout"] == nil)
    }

    @Test("Writing keeps this Mac's settings and merges the file's learned ones")
    func settingsToWrite() {
        let local: [String: Any] = ["KnownItemTags": ["a"], "ShowOnHover": false]
        let remote: [String: Any] = ["KnownItemTags": ["b"], "ShowOnHover": true]
        let written = SettingsSyncPolicy.settingsToWrite(local, file: remote)
        #expect(written["KnownItemTags"] as? [String] == ["a", "b"])
        #expect(written["ShowOnHover"] as? Bool == false)
        #expect(SettingsSyncPolicy.settingsToWrite(local, file: nil)["KnownItemTags"] as? [String] == ["a"])
    }

    // MARK: Digests

    @Test("The digest does not depend on the order of keys")
    func digestKeyOrder() {
        var first = [String: Any]()
        first["ShowOnHover"] = true
        first["Hotkeys"] = ["b": 2, "a": 1]
        var second = [String: Any]()
        second["Hotkeys"] = ["a": 1, "b": 2]
        second["ShowOnHover"] = true
        #expect(SettingsSyncPolicy.digest(of: first) == SettingsSyncPolicy.digest(of: second))
    }

    @Test("JSON in data is compared by its contents")
    func digestJSONData() {
        let first: [String: Any] = ["ItemGroups": Data(#"{"name":"Work","id":1}"#.utf8)]
        let second: [String: Any] = ["ItemGroups": Data(#"{"id":1,"name":"Work"}"#.utf8)]
        let third: [String: Any] = ["ItemGroups": Data(#"{"id":2,"name":"Work"}"#.utf8)]
        #expect(SettingsSyncPolicy.digest(of: first) == SettingsSyncPolicy.digest(of: second))
        #expect(SettingsSyncPolicy.digest(of: first) != SettingsSyncPolicy.digest(of: third))
    }

    @Test("Numbers are compared by value, Booleans apart from numbers")
    func digestNumbers() {
        #expect(SettingsSyncPolicy.digest(of: ["A": 1]) == SettingsSyncPolicy.digest(of: ["A": 1.0]))
        #expect(SettingsSyncPolicy.digest(of: ["A": true]) != SettingsSyncPolicy.digest(of: ["A": 1]))
        #expect(SettingsSyncPolicy.digest(of: ["A": 0.5]) != SettingsSyncPolicy.digest(of: ["A": 1]))
    }

    @Test("A changed value changes the digest")
    func digestChangedValue() {
        #expect(SettingsSyncPolicy.digest(of: ["A": "x"]) != SettingsSyncPolicy.digest(of: ["A": "y"]))
        #expect(SettingsSyncPolicy.digest(of: ["A": "x"]) != SettingsSyncPolicy.digest(of: ["B": "x"]))
        #expect(SettingsSyncPolicy.digest(of: ["A": ["x", "y"]]) != SettingsSyncPolicy.digest(of: ["A": ["y", "x"]]))
    }

    @Test("The digest is 64 lower-case hexadecimal characters")
    func digestFormat() {
        let digest = SettingsSyncPolicy.digest(of: ["A": 1])
        #expect(digest.count == 64)
        #expect(digest.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test("The digest survives a round trip through the sync file")
    func digestPropertyListRoundTrip() throws {
        let settings: [String: Any] = [
            "ShowOnHover": true,
            "RehideInterval": 12.5,
            "SpacerCount": 2,
            "Hotkeys": ["toggle": ["key": 3, "modifiers": 256]],
            "ItemGroups": Data(#"{"b":[1,2],"a":true}"#.utf8),
            "KnownItemTags": ["a", "b"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
        let decoded = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(SettingsSyncPolicy.userDigest(of: decoded) == SettingsSyncPolicy.userDigest(of: settings))
    }

    @Test("The user digest ignores keys holzBar does not apply")
    func userDigestIgnoresForeignKeys() {
        let settings: [String: Any] = ["ShowOnHover": true]
        let withForeign: [String: Any] = ["ShowOnHover": true, "SyncsSettingsWithICloud": true, "NSWindow Frame": "x"]
        #expect(SettingsSyncPolicy.userDigest(of: settings) == SettingsSyncPolicy.userDigest(of: withForeign))
    }
}
