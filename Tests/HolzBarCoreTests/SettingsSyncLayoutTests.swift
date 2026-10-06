import Foundation
import Testing
@testable import HolzBarCore

/// A Mac before macOS 27 and a macOS 27 Mac: every direction test runs for both.
private let layoutBackends: [MenuBarBackendKind] = [.service26, .accessibility27]

@Suite("SettingsSyncPolicy layouts")
struct SettingsSyncLayoutTests {
    private typealias Policy = SettingsSyncPolicy

    private let lastSynced = Date(timeIntervalSince1970: 1_000_000)

    private let first: [String: Any] = ["a": 0, "b": 1]
    private let second: [String: Any] = ["a": 1, "b": 1]
    private let third: [String: Any] = ["a": 2, "c": 1]

    /// A Mac's settings: a user setting, the layouts and this Mac's learned list, as given.
    private func settings(
        _ layouts: Policy.Layouts,
        showOnHover: Bool = true,
        own: [String: Any]? = nil,
        other: [String: Any]? = nil,
        ownKnown: [String]? = nil
    ) -> [String: Any] {
        var settings: [String: Any] = ["ShowOnHover": showOnHover]
        settings[layouts.own] = own
        settings[layouts.other] = other
        settings[layouts.ownKnown] = ownKnown
        return settings
    }

    /// This Mac's side, with the real digests of `settings`.
    private func local(
        _ settings: [String: Any],
        _ layouts: Policy.Layouts,
        base: [String: Any]?,
        baseLayout: [String: Any]? = nil,
        editsLayout: Bool = false,
        pending: Date? = nil
    ) -> Policy.Local {
        Policy.Local(
            settings: settings,
            layouts: layouts,
            base: base.map(Policy.userDigest(of:)),
            baseLayoutDigest: (baseLayout ?? base).map { Policy.layoutDigest(of: $0, layouts: layouts) },
            editsLayout: editsLayout,
            pending: pending,
            postponed: nil,
            forcesWrite: false
        )
    }

    /// A version of the sync file from another Mac, with the real digests of `settings`.
    private func version(_ settings: [String: Any], _ layouts: Policy.Layouts, isNewer: Bool = true) -> Policy.File {
        .version(
            Policy.Version(
                settings: settings,
                layouts: layouts,
                isFromThisMac: false,
                modified: lastSynced.addingTimeInterval(60),
                isNewer: isNewer
            )
        )
    }

    /// Whether `value` is the layout `layout`.
    private func isLayout(_ value: Any?, _ layout: [String: Any]) -> Bool {
        guard let value else {
            return false
        }
        return Policy.digest(of: ["layout": value]) == Policy.digest(of: ["layout": layout])
    }

    // MARK: Keys and digests

    @Test("Each macOS version has its own layout key")
    func layoutKeys() {
        let windowList = Policy.Layouts(backend: .windowList)
        #expect(windowList == Policy.Layouts(backend: .service26))
        #expect(windowList.own == "ItemSections")
        #expect(windowList.other == "MacOS27Layout")
        #expect(windowList.ownKnown == "KnownItemTags")
        let mac27 = Policy.Layouts(backend: .accessibility27)
        #expect(mac27.own == "MacOS27Layout")
        #expect(mac27.other == "ItemSections")
        #expect(mac27.ownKnown == "KnownApplications27")
        #expect(Policy.layoutKeys == ["ItemSections", "MacOS27Layout"])
    }

    @Test("The user digest leaves out both layouts", arguments: layoutBackends)
    func userDigestWithoutLayouts(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let plain = Policy.userDigest(of: settings(layouts))
        #expect(Policy.userDigest(of: settings(layouts, own: first, other: second)) == plain)
        #expect(Policy.userDigest(of: settings(layouts, own: third)) == plain)
        #expect(Policy.userDigest(of: settings(layouts, other: third)) == plain)
        #expect(Policy.userDigest(of: settings(layouts, showOnHover: false, own: first)) != plain)
    }

    @Test("The layout digest sees only this Mac's layout key", arguments: layoutBackends)
    func layoutDigest(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let digest = Policy.layoutDigest(of: settings(layouts, own: first), layouts: layouts)
        #expect(Policy.layoutDigest(of: settings(layouts, showOnHover: false, own: first, other: third), layouts: layouts) == digest)
        #expect(Policy.layoutDigest(of: settings(layouts, own: second), layouts: layouts) != digest)
        #expect(Policy.layoutDigest(of: settings(layouts, other: first), layouts: layouts) == Policy.noLayoutDigest)
        #expect(Policy.layoutDigest(of: [layouts.own: "not a layout"], layouts: layouts) == Policy.noLayoutDigest)
        let reordered: [String: Any] = ["b": 1.0, "a": 0]
        #expect(Policy.layoutDigest(of: [layouts.own: reordered], layouts: layouts) == digest)
    }

    @Test("Only the layouts a file lists as current are used")
    func staleLayouts() {
        let all: [String: Any] = ["ShowOnHover": true, "ItemSections": first, "MacOS27Layout": second, "KnownItemTags": ["a"]]
        #expect(Set(Policy.withoutStaleLayouts(all, currentLayouts: []).keys) == ["ShowOnHover", "KnownItemTags"])
        let one = Policy.withoutStaleLayouts(all, currentLayouts: ["ItemSections", "Unknown"])
        #expect(Set(one.keys) == ["ShowOnHover", "KnownItemTags", "ItemSections"])
        let both = Policy.withoutStaleLayouts(all, currentLayouts: ["ItemSections", "MacOS27Layout"])
        #expect(Set(both.keys) == Set(all.keys))
    }

    // MARK: Writing

    @Test("A write keeps the file's layout of the other macOS version, never this Mac's copy", arguments: layoutBackends)
    func writeKeepsOtherLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, showOnHover: false, own: first, other: second)
        let file = settings(layouts, own: first, other: third)
        let listed = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [layouts.other], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(listed.settings[layouts.other], third))
        #expect(listed.settings["ShowOnHover"] as? Bool == false)
        #expect(listed.currentLayouts == [layouts.own, layouts.other].sorted())
        // A copy from a file of an earlier build is carried on for those builds, but not listed.
        let unlisted = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(unlisted.settings[layouts.other], third))
        #expect(unlisted.currentLayouts == [layouts.own])
        let without = Policy.fileToWrite(
            mine,
            file: settings(layouts, own: first),
            fileCurrentLayouts: [layouts.own],
            layouts: layouts,
            keepsOwnLayout: true
        )
        #expect(without.settings[layouts.other] == nil)
        #expect(without.currentLayouts == [layouts.own])
        let empty = Policy.fileToWrite(mine, file: nil, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: false)
        #expect(empty.settings[layouts.other] == nil)
        #expect(isLayout(empty.settings[layouts.own], first))
        #expect(empty.currentLayouts == [layouts.own])
    }

    @Test("Without a layout change of the user's, a write keeps the file's layout and adds only items it has never seen", arguments: layoutBackends)
    func writeOwnLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: ["a": 2, "known": 2, "new": 1])
        let file = settings(layouts, own: ["a": 0], ownKnown: ["known"])
        let kept = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: false)
        #expect(isLayout(kept.settings[layouts.own], ["a": 0, "new": 1]))
        #expect(kept.currentLayouts == [layouts.own])
        // A layout change of the user's, or "Keep This Mac's Settings", writes this Mac's.
        let edited = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(edited.settings[layouts.own], ["a": 2, "known": 2, "new": 1]))
        // So does a file without a current layout for this macOS version.
        let unlisted = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: false)
        #expect(isLayout(unlisted.settings[layouts.own], ["a": 2, "known": 2, "new": 1]))
        #expect(unlisted.currentLayouts == [layouts.own])
        let missing = Policy.fileToWrite(mine, file: settings(layouts), fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: false)
        #expect(isLayout(missing.settings[layouts.own], ["a": 2, "known": 2, "new": 1]))
        // A Mac without a layout of its own passes the file's on as it is.
        let bare = Policy.fileToWrite(settings(layouts), file: file, fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(bare.settings[layouts.own], ["a": 0]))
        #expect(bare.currentLayouts == [layouts.own])
        let bareUnlisted = Policy.fileToWrite(settings(layouts), file: file, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(bareUnlisted.settings[layouts.own], ["a": 0]))
        #expect(bareUnlisted.currentLayouts.isEmpty)
    }

    // MARK: Applying and taking in

    @Test("Applying takes the other macOS version's layout from the version, and keeps this Mac's when it has none", arguments: layoutBackends)
    func applyOtherLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: first, other: second)
        let synced = Policy.layoutDigest(of: mine, layouts: layouts)
        let applied = Policy.settingsToApply(
            settings(layouts, showOnHover: false, other: third),
            over: mine,
            layouts: layouts,
            baseLayoutDigest: synced,
            editsLayout: false
        )
        #expect(isLayout(applied[layouts.other], third))
        #expect(applied["ShowOnHover"] as? Bool == false)
        #expect(applied[layouts.own] == nil)
        let without = Policy.settingsToApply(settings(layouts, showOnHover: false), over: mine, layouts: layouts, baseLayoutDigest: synced, editsLayout: false)
        // Applying never removes a key, so this Mac's layouts stay.
        #expect(without[layouts.other] == nil)
        #expect(without[layouts.own] == nil)
    }

    @Test("Applying keeps this Mac's layout when the version did not change it since the last sync", arguments: layoutBackends)
    func applyKeepsOwnLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // holzBar placed an item since the last sync.
        let mine = settings(layouts, own: ["a": 0, "placed": 1])
        let synced = Policy.layoutDigest(of: settings(layouts, own: ["a": 0]), layouts: layouts)
        let remote = settings(layouts, showOnHover: false, own: ["a": 0])
        let applied = Policy.settingsToApply(remote, over: mine, layouts: layouts, baseLayoutDigest: synced, editsLayout: false)
        #expect(applied[layouts.own] == nil)
        #expect(applied["ShowOnHover"] as? Bool == false)
        // After a layout change of the user's, the version's layout is taken, with this
        // Mac's items it has never seen.
        let edited = settings(layouts, own: ["a": 2, "placed": 1])
        let chosen = Policy.settingsToApply(remote, over: edited, layouts: layouts, baseLayoutDigest: synced, editsLayout: true)
        #expect(isLayout(chosen[layouts.own], ["a": 0, "placed": 1]))
    }

    @Test("Applying a changed layout keeps this Mac's items the version has never seen", arguments: layoutBackends)
    func applyMergesOwnLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: ["a": 0, "known": 2, "unseen": 1])
        let remote = settings(layouts, own: ["a": 1], ownKnown: ["known"])
        let synced = Policy.layoutDigest(of: settings(layouts, own: ["a": 0]), layouts: layouts)
        let applied = Policy.settingsToApply(remote, over: mine, layouts: layouts, baseLayoutDigest: synced, editsLayout: false)
        #expect(isLayout(applied[layouts.own], ["a": 1, "unseen": 1]))
    }

    @Test("The other macOS version's layout is taken in only when it differs", arguments: layoutBackends)
    func takeInOtherLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: first, other: second)
        let takenIn = Policy.layoutToTakeIn(settings(layouts, own: second, other: third), over: mine, layouts: layouts)
        #expect(Set(takenIn.keys) == [layouts.other])
        #expect(isLayout(takenIn[layouts.other], third))
        #expect(Policy.layoutToTakeIn(settings(layouts, other: second), over: mine, layouts: layouts).isEmpty)
        #expect(Policy.layoutToTakeIn(settings(layouts, own: third), over: mine, layouts: layouts).isEmpty)
        let fresh = Policy.layoutToTakeIn(settings(layouts, other: third), over: settings(layouts, own: first), layouts: layouts)
        #expect(isLayout(fresh[layouts.other], third))
    }

    // MARK: Joining

    @Test("A Mac before macOS 27 and a macOS 27 Mac with otherwise equal settings never ask when one joins", arguments: layoutBackends)
    func joiningAcrossVersionsNeverAsks(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: first, other: second)
        // Files written by a Mac of the other macOS version, which lists its own layout.
        let files: [[String: Any]] = [
            // Without this Mac's layout key.
            settings(layouts, other: third),
            // With this Mac's layout, listed and equal.
            settings(layouts, own: first, other: third),
            // With this Mac's layout as it was at its last sync, listed.
            settings(layouts, own: third, other: third),
            // With an unlisted copy from an earlier build.
            Policy.withoutStaleLayouts(settings(layouts, own: second, other: third), currentLayouts: [layouts.other]),
        ]
        for file in files {
            for editsLayout in [false, true] {
                let joining = local(mine, layouts, base: nil, baseLayout: settings(layouts, own: third), editsLayout: editsLayout)
                for trigger in [Policy.Trigger.localChange, .check, .launch] {
                    #expect(Policy.decide(trigger, local: joining, file: version(file, layouts)) != .ask)
                }
            }
        }
        // A real difference still asks.
        let joining = local(mine, layouts, base: nil)
        #expect(Policy.decide(.check, local: joining, file: version(settings(layouts, showOnHover: false, other: third), layouts)) == .ask)
    }

    @Test("Joining without a layout change of the user's does not ask about another layout of the same macOS version", arguments: layoutBackends)
    func joiningWithoutEditsAdopts(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let joining = local(settings(layouts, own: first), layouts, base: nil)
        let file = version(settings(layouts, own: third), layouts)
        for trigger in [Policy.Trigger.localChange, .check, .launch] {
            #expect(Policy.decide(trigger, local: joining, file: file) == .adopt)
        }
    }

    @Test("Joining after a layout change of the user's asks only about another user's layout", arguments: layoutBackends)
    func joiningWithEdits(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let joining = local(settings(layouts, own: first), layouts, base: nil, baseLayout: settings(layouts, own: second), editsLayout: true)
        #expect(Policy.decide(.check, local: joining, file: version(settings(layouts, own: third), layouts)) == .ask)
        // The same layout is adopted.
        #expect(Policy.decide(.check, local: joining, file: version(settings(layouts, own: first), layouts)) == .adopt)
        // A file without this macOS version's layout, or with the one this Mac last synced, is written.
        for file in [settings(layouts), settings(layouts, own: second)] {
            #expect(Policy.decide(.localChange, local: joining, file: version(file, layouts)) == .write)
            #expect(Policy.decide(.check, local: joining, file: version(file, layouts)) == .write)
            #expect(Policy.decide(.launch, local: joining, file: version(file, layouts)) == .none)
        }
    }

    @Test("A layout from a file of an earlier build is neither compared nor applied", arguments: layoutBackends)
    func earlierBuildLayoutIgnored(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let current = Policy.withoutStaleLayouts(settings(layouts, own: third, other: second), currentLayouts: [])
        let earlier = Policy.Version(settings: current, layouts: layouts, isFromThisMac: false, modified: lastSynced, isNewer: true)
        #expect(earlier.layoutDigest == nil)
        let mine = settings(layouts, own: first)
        let synced = local(mine, layouts, base: mine)
        #expect(Policy.decide(.check, local: synced, file: version(current, layouts)) == .adopt)
        let joining = local(mine, layouts, base: nil, editsLayout: true)
        #expect(Policy.decide(.check, local: joining, file: version(current, layouts)) == .write)
        let applied = Policy.settingsToApply(current, over: mine, layouts: layouts, baseLayoutDigest: synced.baseLayoutDigest, editsLayout: true)
        #expect(applied[layouts.own] == nil)
        #expect(applied[layouts.other] == nil)
        #expect(Policy.layoutToTakeIn(current, over: mine, layouts: layouts).isEmpty)
    }

    // MARK: Running

    @Test("A newer version that changed only the other macOS version's layout is adopted", arguments: layoutBackends)
    func otherLayoutChangeAdopted(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: first, other: second)
        let synced = local(mine, layouts, base: mine)
        for remote in [settings(layouts, own: first, other: third), settings(layouts, other: third)] {
            #expect(Policy.decide(.check, local: synced, file: version(remote, layouts)) == .adopt)
            #expect(Policy.decide(.launch, local: synced, file: version(remote, layouts)) == .adopt)
        }
    }

    @Test("A layout change here and one of the other macOS version there do not ask", arguments: layoutBackends)
    func layoutChangesOnBothVersions(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let syncedSettings = settings(layouts, own: first, other: second)
        let edited = local(settings(layouts, own: third, other: second), layouts, base: syncedSettings, editsLayout: true)
        let remote = version(settings(layouts, own: first, other: third), layouts)
        #expect(Policy.decide(.localChange, local: edited, file: remote) == .write)
        #expect(Policy.decide(.check, local: edited, file: remote) == .write)
        #expect(Policy.decide(.launch, local: edited, file: remote) == .none)
    }

    @Test("holzBar's own placements never count as a change", arguments: layoutBackends)
    func automaticPlacementsDoNotCount(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let synced = settings(layouts, own: first)
        let placed = settings(layouts, own: ["a": 0, "b": 1, "new": 1])
        let waiting = local(placed, layouts, base: synced, pending: lastSynced.addingTimeInterval(60))
        #expect(!waiting.hasChanges)
        #expect(Policy.hint(for: waiting) == .restart)
        let running = local(placed, layouts, base: synced)
        #expect(!Policy.needsExchange(.localChange, local: running))
        let remote = version(settings(layouts, showOnHover: false, own: first), layouts)
        #expect(Policy.decide(.check, local: running, file: remote) == .apply)
        #expect(Policy.decide(.launch, local: running, file: remote) == .apply)
    }

    @Test("A layout change of the user's counts as a change", arguments: layoutBackends)
    func userLayoutChangeCounts(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let synced = settings(layouts, own: first)
        let moved = settings(layouts, own: ["a": 2, "b": 1])
        let waiting = local(moved, layouts, base: synced, editsLayout: true, pending: lastSynced.addingTimeInterval(60))
        #expect(waiting.hasChanges)
        #expect(Policy.hint(for: waiting) == .choice(isJoining: false))
        let running = local(moved, layouts, base: synced, editsLayout: true)
        #expect(Policy.needsExchange(.localChange, local: running))
        let remote = version(settings(layouts, showOnHover: false, own: first), layouts)
        #expect(Policy.decide(.check, local: running, file: remote) == .ask)
    }

    @Test("A newer version equal to the last sync lets this Mac's changes win")
    func unchangedVersionLetsChangesWin() {
        let changed = Policy.Local(userDigest: "changed", base: "base", pending: nil, postponed: nil, forcesWrite: false)
        let unchanged = Policy.File.version(
            Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(60), isNewer: true, userDigest: "base")
        )
        #expect(Policy.decide(.localChange, local: changed, file: unchanged) == .write)
        #expect(Policy.decide(.check, local: changed, file: unchanged) == .write)
        #expect(Policy.decide(.launch, local: changed, file: unchanged) == .none)
        // A version whose layout changed since the last sync is a change of its own.
        var withLayout = changed
        withLayout.baseLayoutDigest = "layout"
        let relaid = Policy.File.version(
            Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(60), isNewer: true, userDigest: "base", layoutDigest: "other")
        )
        #expect(Policy.decide(.check, local: withLayout, file: relaid) == .ask)
    }

    @Test("The hint offers a restart exactly where a newer version is applied, also with layouts", arguments: layoutBackends)
    func hintMatchesDecisionWithLayouts(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let synced = settings(layouts, own: first)
        let versions = [
            settings(layouts, showOnHover: false, own: first),
            settings(layouts, showOnHover: false, own: second),
            settings(layouts, own: second),
            settings(layouts, showOnHover: false),
        ]
        for showOnHover in [true, false] {
            for own in [first, third] {
                for editsLayout in [false, true] {
                    for base in [synced, nil] {
                        let candidate = local(
                            settings(layouts, showOnHover: showOnHover, own: own),
                            layouts,
                            base: base,
                            baseLayout: synced,
                            editsLayout: editsLayout
                        )
                        let hint = Policy.hint(for: candidate)
                        for remote in versions {
                            let action = Policy.decide(.check, local: candidate, file: version(remote, layouts))
                            guard action == .apply || action == .ask else {
                                continue
                            }
                            #expect((action == .apply) == (hint == .restart))
                        }
                    }
                }
            }
        }
    }
}
