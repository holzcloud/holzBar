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

    /// A version of the sync file from another Mac, as the decision sees it.
    private func newerVersion(_ settings: [String: Any], _ layouts: Policy.Layouts, isNewer: Bool = true) -> Policy.Version {
        Policy.Version(settings: settings, layouts: layouts, isFromThisMac: false, modified: lastSynced.addingTimeInterval(60), isNewer: isNewer)
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

    @Test("A write keeps the file's layout of the other macOS version, and adds this Mac's copy unlisted only when the file has none", arguments: layoutBackends)
    func writeKeepsOtherLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, showOnHover: false, own: first, other: second)
        let file = settings(layouts, own: first, other: third)
        let listed = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [layouts.other], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(listed.settings[layouts.other], third))
        #expect(listed.settings["ShowOnHover"] as? Bool == false)
        #expect(listed.currentLayouts == [layouts.own, layouts.other].sorted())
        #expect(listed.copiedLayouts.isEmpty)
        // A copy from a file of an earlier build is carried on for those builds, but not listed.
        let unlisted = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(unlisted.settings[layouts.other], third))
        #expect(unlisted.currentLayouts == [layouts.own])
        #expect(unlisted.copiedLayouts.isEmpty)
        // A copy's mark is passed on with it.
        let marked = Policy.fileToWrite(
            mine,
            file: file,
            fileCurrentLayouts: [],
            fileCopiedLayouts: [layouts.other],
            layouts: layouts,
            keepsOwnLayout: true
        )
        #expect(isLayout(marked.settings[layouts.other], third))
        #expect(marked.copiedLayouts == [layouts.other])
        let without = Policy.fileToWrite(
            mine,
            file: settings(layouts, own: first),
            fileCurrentLayouts: [layouts.own],
            layouts: layouts,
            keepsOwnLayout: true
        )
        // Without one, this Mac's copy is written for builds before this one, which would
        // otherwise delete that layout (F-60), but not listed: this build ignores it.
        #expect(isLayout(without.settings[layouts.other], second))
        #expect(without.currentLayouts == [layouts.own])
        #expect(without.copiedLayouts == [layouts.other])
        #expect(Policy.withoutStaleLayouts(without.settings, currentLayouts: Set(without.currentLayouts))[layouts.other] == nil)
        let empty = Policy.fileToWrite(mine, file: nil, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: false)
        #expect(isLayout(empty.settings[layouts.other], second))
        #expect(isLayout(empty.settings[layouts.own], first))
        #expect(empty.currentLayouts == [layouts.own])
        #expect(empty.copiedLayouts == [layouts.other])
        // A Mac without a copy writes none.
        let bare = Policy.fileToWrite(settings(layouts, own: first), file: nil, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: false)
        #expect(bare.settings[layouts.other] == nil)
        #expect(bare.copiedLayouts.isEmpty)
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
        // A layout an earlier build wrote, unlisted, is passed on as it is, unlisted.
        let unlisted = Policy.fileToWrite(mine, file: file, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: false)
        #expect(isLayout(unlisted.settings[layouts.own], ["a": 0]))
        #expect(unlisted.currentLayouts.isEmpty)
        // So is a file without a current layout for this macOS version.
        let missing = Policy.fileToWrite(mine, file: settings(layouts), fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: false)
        #expect(isLayout(missing.settings[layouts.own], ["a": 2, "known": 2, "new": 1]))
        // A Mac without a layout of its own passes the file's on as it is.
        let bare = Policy.fileToWrite(settings(layouts), file: file, fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(bare.settings[layouts.own], ["a": 0]))
        #expect(bare.currentLayouts == [layouts.own])
        let bareUnlisted = Policy.fileToWrite(settings(layouts), file: file, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(bareUnlisted.settings[layouts.own], ["a": 0]))
        #expect(bareUnlisted.currentLayouts.isEmpty)
        #expect(bareUnlisted.copiedLayouts.isEmpty)
        let bareCopy = Policy.fileToWrite(
            settings(layouts),
            file: file,
            fileCurrentLayouts: [],
            fileCopiedLayouts: [layouts.own],
            layouts: layouts,
            keepsOwnLayout: false
        )
        #expect(isLayout(bareCopy.settings[layouts.own], ["a": 0]))
        #expect(bareCopy.copiedLayouts == [layouts.own])
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
        // A Mac of the other macOS version marks its copy of this Mac's layout as a copy:
        // it is no arrangement to ask about, and this Mac writes its own layout over it.
        let copy = settings(layouts, own: second, other: third)
        let copyFile = Policy.Version(
            settings: Policy.withoutStaleLayouts(copy, currentLayouts: [layouts.other]),
            layouts: layouts,
            isFromThisMac: false,
            modified: lastSynced.addingTimeInterval(60),
            isNewer: true,
            unlistedLayoutDigest: Policy.unlistedLayoutDigest(
                in: copy,
                currentLayouts: [layouts.other],
                copiedLayouts: [layouts.own],
                layouts: layouts
            )
        )
        #expect(copyFile.unlistedLayoutDigest == nil)
        for editsLayout in [false, true] {
            let joining = local(mine, layouts, base: nil, baseLayout: settings(layouts, own: third), editsLayout: editsLayout)
            for trigger in [Policy.Trigger.localChange, .check, .launch] {
                #expect(Policy.decide(trigger, local: joining, file: .version(copyFile)) != .ask)
            }
        }
        let overCopy = Policy.fileToWrite(
            mine,
            file: copy,
            fileCurrentLayouts: [layouts.other],
            fileCopiedLayouts: [layouts.own],
            layouts: layouts,
            keepsOwnLayout: false
        )
        #expect(isLayout(overCopy.settings[layouts.own], first))
        #expect(overCopy.currentLayouts == [layouts.own, layouts.other].sorted())
        #expect(overCopy.copiedLayouts.isEmpty)
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

    @Test("A joining Mac without a layout change of the user's takes in the folder's layout of its macOS version", arguments: layoutBackends)
    func joiningTakesInOwnLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: ["a": 0, "known": 2, "unseen": 1], other: second)
        let remote = settings(layouts, own: ["a": 1], other: third, ownKnown: ["known"])
        let joining = local(mine, layouts, base: nil)
        #expect(Policy.decide(.check, local: joining, file: version(remote, layouts)) == .adopt)
        let takenIn = Policy.ownLayoutToTakeIn(remote, over: mine, layouts: layouts, local: joining, version: newerVersion(remote, layouts))
        #expect(Set(takenIn.keys) == [layouts.own])
        #expect(isLayout(takenIn[layouts.own], ["a": 1, "unseen": 1]))

        // While holzBar runs, the Mac records its own layout as synced: the version is then
        // applied by Restart or at the next launch, with the same layout.
        let recorded = local(mine, layouts, base: mine)
        #expect(!recorded.hasChanges)
        #expect(Policy.decide(.check, local: recorded, file: version(remote, layouts)) == .apply)
        #expect(Policy.decide(.launch, local: recorded, file: version(remote, layouts)) == .apply)
        #expect(Policy.hint(for: recorded) == .restart)
        let applied = Policy.settingsToApply(
            remote,
            over: mine,
            layouts: layouts,
            baseLayoutDigest: recorded.baseLayoutDigest,
            editsLayout: false
        )
        #expect(isLayout(applied[layouts.own], ["a": 1, "unseen": 1]))

        // Nothing is taken in after a layout change of the user's, by a Mac that is not
        // joining, from a version this Mac already synced, without a current layout of
        // this macOS version, or when this Mac already holds it.
        let edited = local(mine, layouts, base: nil, editsLayout: true)
        #expect(Policy.ownLayoutToTakeIn(remote, over: mine, layouts: layouts, local: edited, version: newerVersion(remote, layouts)).isEmpty)
        #expect(Policy.ownLayoutToTakeIn(remote, over: mine, layouts: layouts, local: recorded, version: newerVersion(remote, layouts)).isEmpty)
        #expect(Policy.ownLayoutToTakeIn(remote, over: mine, layouts: layouts, local: joining, version: newerVersion(remote, layouts, isNewer: false)).isEmpty)
        let stale = Policy.withoutStaleLayouts(remote, currentLayouts: [layouts.other])
        #expect(Policy.ownLayoutToTakeIn(stale, over: mine, layouts: layouts, local: joining, version: newerVersion(remote, layouts)).isEmpty)
        let held = settings(layouts, own: ["a": 1, "unseen": 1])
        #expect(Policy.ownLayoutToTakeIn(remote, over: held, layouts: layouts, local: local(held, layouts, base: nil), version: newerVersion(remote, layouts)).isEmpty)

        // A fresh install takes in the folder's layout as it is.
        let fresh = settings(layouts)
        let freshTakenIn = Policy.ownLayoutToTakeIn(remote, over: fresh, layouts: layouts, local: local(fresh, layouts, base: nil), version: newerVersion(remote, layouts))
        #expect(isLayout(freshTakenIn[layouts.own], ["a": 1]))
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
        // A file that holds no layout for this macOS version is written after a change.
        let joining = local(mine, layouts, base: nil, editsLayout: true)
        #expect(Policy.decide(.check, local: joining, file: version(current, layouts)) == .write)
        let applied = Policy.settingsToApply(current, over: mine, layouts: layouts, baseLayoutDigest: synced.baseLayoutDigest, editsLayout: true)
        #expect(applied[layouts.own] == nil)
        #expect(applied[layouts.other] == nil)
        #expect(Policy.layoutToTakeIn(current, over: mine, layouts: layouts).isEmpty)
    }

    // MARK: Files of earlier builds

    /// A version of a file an earlier build wrote: its layouts are unlisted.
    private func earlierVersion(_ file: [String: Any], _ layouts: Policy.Layouts, fromThisMac: Bool = false, isNewer: Bool = true) -> Policy.File {
        .version(
            Policy.Version(
                settings: Policy.withoutStaleLayouts(file, currentLayouts: []),
                layouts: layouts,
                isFromThisMac: fromThisMac,
                modified: lastSynced.addingTimeInterval(60),
                isNewer: isNewer,
                unlistedLayoutDigest: Policy.unlistedLayoutDigest(in: file, currentLayouts: [], layouts: layouts)
            )
        )
    }

    @Test("Only a layout for this macOS version that the file holds but does not list counts as unlisted", arguments: layoutBackends)
    func unlistedLayoutDigest(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let file = settings(layouts, own: first, other: second)
        #expect(Policy.unlistedLayoutDigest(in: file, currentLayouts: [], layouts: layouts) == Policy.layoutDigest(of: file, layouts: layouts))
        #expect(Policy.unlistedLayoutDigest(in: file, currentLayouts: [layouts.other], layouts: layouts) != nil)
        #expect(Policy.unlistedLayoutDigest(in: file, currentLayouts: [layouts.own], layouts: layouts) == nil)
        #expect(Policy.unlistedLayoutDigest(in: settings(layouts, other: second), currentLayouts: [], layouts: layouts) == nil)
        #expect(Policy.unlistedLayoutDigest(in: [layouts.own: "not a layout"], currentLayouts: [], layouts: layouts) == nil)
    }

    @Test("A write without a layout change of the user's never replaces a layout of this macOS version that an earlier build wrote", arguments: layoutBackends)
    func writeKeepsEarlierBuildLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // A Mac of this macOS version still on 0.0.7 beta 1 arranged `third`; its file lists no layout.
        let beta1File = settings(layouts, own: third, other: second)
        let mine = settings(layouts, showOnHover: false, own: first, other: second)
        // This Mac adopted that file without taking its layout in.
        let adopted = local(settings(layouts, own: first, other: second), layouts, base: settings(layouts), baseLayout: settings(layouts))
        #expect(Policy.decide(.check, local: adopted, file: earlierVersion(beta1File, layouts)) == .adopt)
        // A change of a user setting writes, and keeps that Mac's layout as it is, unlisted.
        var changed = local(mine, layouts, base: settings(layouts), baseLayout: settings(layouts))
        #expect(Policy.decide(.localChange, local: changed, file: earlierVersion(beta1File, layouts)) == .write)
        let written = Policy.fileToWrite(mine, file: beta1File, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: false)
        #expect(isLayout(written.settings[layouts.own], third))
        #expect(!written.currentLayouts.contains(layouts.own))
        #expect(written.settings["ShowOnHover"] as? Bool == false)
        // This Mac has not taken that layout in, so it records none as synced.
        let current = Set(written.currentLayouts)
        #expect(Policy.syncedLayoutDigest(afterWriting: written.settings, currentLayouts: current, layouts: layouts, local: changed) == nil)
        // The file this Mac then wrote still holds it, and a layout change of the user's asks.
        changed.editsLayout = true
        let ownFile = Policy.File.version(
            Policy.Version(
                settings: Policy.withoutStaleLayouts(written.settings, currentLayouts: current),
                layouts: layouts,
                isFromThisMac: true,
                modified: lastSynced.addingTimeInterval(120),
                isNewer: false,
                unlistedLayoutDigest: Policy.unlistedLayoutDigest(in: written.settings, currentLayouts: current, layouts: layouts)
            )
        )
        #expect(Policy.decide(.localChange, local: changed, file: ownFile) == .ask)
    }

    @Test("A layout change of the user's asks before it replaces a layout of this macOS version that an earlier build wrote", arguments: layoutBackends)
    func layoutChangeAsksAboutEarlierBuildLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let beta1File = settings(layouts, own: third, other: second)
        let moved = settings(layouts, own: second)
        let edited = local(moved, layouts, base: moved, baseLayout: settings(layouts), editsLayout: true)
        for trigger in [Policy.Trigger.localChange, .check, .launch] {
            #expect(Policy.decide(trigger, local: edited, file: earlierVersion(beta1File, layouts)) == .ask)
            #expect(Policy.decide(trigger, local: edited, file: earlierVersion(beta1File, layouts, fromThisMac: true, isNewer: false)) == .ask)
            #expect(Policy.decide(trigger, local: edited, file: earlierVersion(beta1File, layouts, isNewer: false)) == .ask)
        }
        #expect(Policy.hint(for: edited) == .choice(isJoining: false))
        // "Later" waits for that version.
        var postponed = edited
        postponed.postponed = lastSynced.addingTimeInterval(60)
        #expect(Policy.decide(.check, local: postponed, file: earlierVersion(beta1File, layouts)) == .wait)
        // A joining Mac whose layout the user changed asks too.
        let joining = local(moved, layouts, base: nil, baseLayout: settings(layouts), editsLayout: true)
        #expect(Policy.decide(.check, local: joining, file: earlierVersion(beta1File, layouts)) == .ask)
        // Nothing is lost when the layout is this Mac's, or the one it last synced.
        let same = local(settings(layouts, own: third), layouts, base: moved, baseLayout: settings(layouts), editsLayout: true)
        #expect(Policy.decide(.localChange, local: same, file: earlierVersion(beta1File, layouts)) == .write)
        let syncedIt = local(moved, layouts, base: moved, baseLayout: settings(layouts, own: third), editsLayout: true)
        #expect(Policy.decide(.localChange, local: syncedIt, file: earlierVersion(beta1File, layouts)) == .write)
        // "Keep This Mac's Settings" writes.
        var keeps = edited
        keeps.forcesWrite = true
        keeps.keepsOver = lastSynced.addingTimeInterval(60)
        #expect(Policy.decide(.localChange, local: keeps, file: earlierVersion(beta1File, layouts)) == .write)
        let kept = Policy.fileToWrite(moved, file: beta1File, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(kept.settings[layouts.own], second))
        #expect(kept.currentLayouts.contains(layouts.own))
        // Without a layout change of the user's, nothing asks.
        let unchanged = local(settings(layouts, showOnHover: false, own: second), layouts, base: settings(layouts), baseLayout: settings(layouts))
        #expect(Policy.decide(.localChange, local: unchanged, file: earlierVersion(beta1File, layouts)) == .write)
    }

    @Test("An old copy of this Mac's layout that a Mac still on 0.0.7 beta 1 writes back is written over without a question", arguments: layoutBackends)
    func staleCopyOfOwnLayoutWrittenOver(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let oldLayout: [String: Any] = ["x": 2]
        let currentLayout: [String: Any] = ["x": 1, "y": 2]
        // This Mac synced `oldLayout`, then `currentLayout`. A beta 1 Mac, of either macOS
        // version, applied a file with `oldLayout` and writes it back, unlisted.
        var state = Policy.State(lastSynced: lastSynced)
        state.markSynced(base: Policy.userDigest(of: settings(layouts)), layout: Policy.layoutDigest(of: [layouts.own: oldLayout], layouts: layouts), layoutEdits: 0, modified: lastSynced)
        state.markSynced(base: Policy.userDigest(of: settings(layouts)), layout: Policy.layoutDigest(of: [layouts.own: currentLayout], layouts: layouts), layoutEdits: 0, modified: lastSynced)
        let beta1File = settings(layouts, own: oldLayout, other: ["i": 0])
        let mine = settings(layouts, showOnHover: false, own: currentLayout)

        // A change of a user setting writes this Mac's layout over the old copy, listed.
        let changed = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let written = Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: changed)
        #expect(isLayout(written.settings[layouts.own], currentLayout))
        #expect(written.currentLayouts.contains(layouts.own))
        #expect(written.record.layoutDigest == Policy.layoutDigest(of: mine, layouts: layouts))

        // A drag writes over it without a question, and choosing the folder's settings would
        // not bring it back.
        let dragged = settings(layouts, showOnHover: false, own: ["x": 1, "y": 0])
        let edited = Policy.Local(settings: dragged, layouts: layouts, state: state, layoutEdits: 1, postponed: nil, forcesWrite: false)
        let file = earlierVersion(beta1File, layouts)
        guard case .version(let beta1Version) = file else {
            Issue.record("Expected a version")
            return
        }
        #expect(!Policy.replacesUnlistedLayout(beta1Version, local: edited))
        #expect(Policy.decide(.localChange, local: edited, file: file) == .write)
        let used = Policy.settingsToUse(
            Policy.withoutStaleLayouts(beta1File, currentLayouts: []),
            unlisted: beta1File,
            over: dragged,
            layouts: layouts,
            version: beta1Version,
            local: edited
        )
        #expect(used.settings[layouts.own] == nil)

        // A layout this Mac never synced is still passed on, and a drag still asks.
        let fresh = Policy.State(base: state.base, baseLayoutDigest: state.baseLayoutDigest, lastSynced: lastSynced)
        let unknown = Policy.Local(settings: dragged, layouts: layouts, state: fresh, layoutEdits: 1, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: unknown, file: file) == .ask)
        let unknownChanged = Policy.Local(settings: mine, layouts: layouts, state: fresh, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let passedOn = Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: unknownChanged)
        #expect(isLayout(passedOn.settings[layouts.own], oldLayout))
        #expect(!passedOn.currentLayouts.contains(layouts.own))
    }

    @Test("Choosing the folder's settings over a layout change takes in the layout an earlier build wrote", arguments: layoutBackends)
    func useTakesInEarlierBuildLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let beta1File = settings(layouts, showOnHover: false, own: ["a": 3, "known": 1], other: second, ownKnown: ["known"])
        let current = Policy.withoutStaleLayouts(beta1File, currentLayouts: [])
        guard case .version(let earlier) = earlierVersion(beta1File, layouts) else {
            Issue.record("Expected a version")
            return
        }
        let mine = settings(layouts, own: ["a": 1, "known": 2, "unseen": 1])
        let edited = local(mine, layouts, base: mine, baseLayout: settings(layouts), editsLayout: true)
        let used = Policy.settingsToUse(current, unlisted: beta1File, over: mine, layouts: layouts, version: earlier, local: edited)
        #expect(isLayout(used.settings[layouts.own], ["a": 3, "known": 1, "unseen": 1]))
        #expect(used.settings["ShowOnHover"] as? Bool == false)
        #expect(used.layoutDigest == earlier.unlistedLayoutDigest)
        // Recorded as synced, a later write passes it on and keeps it as synced, so the next
        // layout change of the user's does not ask about it again.
        let after = local(mine, layouts, base: mine, baseLayout: [layouts.own: beta1File[layouts.own] as Any])
        #expect(after.baseLayoutDigest == earlier.unlistedLayoutDigest)
        let written = Policy.fileToWrite(mine, file: beta1File, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: false)
        let current2 = Set(written.currentLayouts)
        #expect(Policy.syncedLayoutDigest(afterWriting: written.settings, currentLayouts: current2, layouts: layouts, local: after) == earlier.unlistedLayoutDigest)
        var nextEdit = after
        nextEdit.editsLayout = true
        #expect(Policy.decide(.localChange, local: nextEdit, file: earlierVersion(beta1File, layouts, fromThisMac: true, isNewer: false)) == .write)
        // Without a question about that layout, the folder's settings apply as before.
        let unedited = local(mine, layouts, base: mine, baseLayout: settings(layouts))
        let plain = Policy.settingsToUse(current, unlisted: beta1File, over: mine, layouts: layouts, version: earlier, local: unedited)
        #expect(plain.settings[layouts.own] == nil)
        #expect(plain.layoutDigest == nil)
        // A listed layout is recorded as written.
        let listed = Policy.fileToWrite(mine, file: nil, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: true)
        let listedDigest = Policy.syncedLayoutDigest(afterWriting: listed.settings, currentLayouts: Set(listed.currentLayouts), layouts: layouts, local: unedited)
        #expect(listedDigest == Policy.layoutDigest(of: mine, layouts: layouts))
    }

    // MARK: Writes that keep another Mac's layout

    /// The version this Mac wrote with `written`, as it reads it back.
    private func ownVersion(_ written: (settings: [String: Any], currentLayouts: [String], copiedLayouts: [String]), _ layouts: Policy.Layouts, modified: Date) -> Policy.File {
        .version(
            Policy.Version(
                settings: Policy.withoutStaleLayouts(written.settings, currentLayouts: Set(written.currentLayouts)),
                layouts: layouts,
                isFromThisMac: true,
                modified: modified,
                isNewer: false
            )
        )
    }

    @Test("Keeping this Mac's settings keeps another Mac's newer layout when the user did not change this Mac's, and takes it in", arguments: layoutBackends)
    func keepThisMacKeepsOtherLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // Synced with `first`; holzBar placed an item since; the user changed a setting.
        let syncedSettings = settings(layouts, own: first)
        let mine = settings(layouts, showOnHover: false, own: ["a": 0, "b": 1, "placed": 1])
        // Another Mac changed the same setting and its arrangement.
        let remote = settings(layouts, showOnHover: true, own: ["a": 5, "b": 1])
        let remoteDigest = Policy.layoutDigest(of: remote, layouts: layouts)
        // The setting was at its default at the last sync; each Mac set it another way.
        var state = Policy.State(
            base: Policy.userDigest(of: settings(layouts).filter { $0.key != "ShowOnHover" }),
            baseLayoutDigest: Policy.layoutDigest(of: syncedSettings, layouts: layouts),
            lastSynced: lastSynced
        )
        var keeps = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: keeps, file: version(remote, layouts)) == .ask)
        keeps.forcesWrite = true
        keeps.keepsOver = lastSynced.addingTimeInterval(60)
        #expect(Policy.decide(.localChange, local: keeps, file: version(remote, layouts)) == .write)
        #expect(!Policy.writesOwnLayout(keeps))
        let written = Policy.fileToWrite(
            mine,
            file: remote,
            fileCurrentLayouts: [layouts.own],
            layouts: layouts,
            keepsOwnLayout: Policy.writesOwnLayout(keeps)
        )
        #expect(isLayout(written.settings[layouts.own], ["a": 5, "b": 1, "placed": 1]))
        #expect(written.settings["ShowOnHover"] as? Bool == false)
        let writtenDigest = Policy.syncedLayoutDigest(
            afterWriting: written.settings,
            currentLayouts: Set(written.currentLayouts),
            layouts: layouts,
            local: keeps
        )
        #expect(Policy.takesInKeptLayout(fileLayoutDigest: remoteDigest, writtenLayoutDigest: writtenDigest, local: keeps))
        let modified = lastSynced.addingTimeInterval(120)
        state.recordWrite(Policy.WriteRecord(layoutDigest: writtenDigest, takesInLayout: true), modified: modified, local: keeps)
        #expect(state.baseLayoutDigest == keeps.layoutDigest)
        #expect(state.lastSynced == modified)
        // The kept layout waits without pausing this Mac's pushes.
        #expect(state.pending == nil)

        // The written version holds the other Mac's layout, which this Mac takes in: by
        // Restart, or at the next launch.
        let after = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let own = ownVersion(written, layouts, modified: modified)
        guard case .version(let ownVersion) = own else {
            Issue.record("Expected a version")
            return
        }
        #expect(Policy.decide(.check, local: after, file: own) == .takeInLayout)
        #expect(Policy.decide(.launch, local: after, file: own) == .takeInLayout)
        #expect(Policy.hint(for: after, version: ownVersion) == .restart)
        let current = Policy.withoutStaleLayouts(written.settings, currentLayouts: Set(written.currentLayouts))
        let takenIn = Policy.keptLayoutToTakeIn(current, over: mine, layouts: layouts)
        #expect(Set(takenIn.keys) == [layouts.own])
        #expect(isLayout(takenIn[layouts.own], ["a": 5, "b": 1, "placed": 1]))
        // Restart takes in only the layout, and records it as synced.
        let used = Policy.settingsToUse(current, unlisted: nil, over: mine, layouts: layouts, version: ownVersion, local: after)
        #expect(Set(used.settings.keys) == [layouts.own])
        #expect(isLayout(used.settings[layouts.own], ["a": 5, "b": 1, "placed": 1]))
        var restarted = state
        restarted.recordUse(of: ownVersion, layoutDigest: used.layoutDigest, base: "not recorded")
        #expect(restarted.base == state.base)
        #expect(restarted.baseLayoutDigest == ownVersion.layoutDigest)
        let afterRestart = Policy.Local(settings: mine.merging(takenIn) { $1 }, layouts: layouts, state: restarted, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: afterRestart, file: own) == .adopt)
        // A layout change of the user's meanwhile asks instead of writing over it.
        let edited = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 1, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: edited, file: own) == .ask)
        #expect(Policy.decide(.localChange, local: edited, file: own) == .ask)
        #expect(Policy.decide(.launch, local: edited, file: own) == .ask)
        #expect(Policy.hint(for: edited, version: ownVersion) == .choice(isJoining: false))
        #expect(Policy.hint(for: after, version: ownVersion, savesLayoutSoon: true) == .choice(isJoining: false))
        var later = edited
        later.postponed = modified
        #expect(Policy.decide(.check, local: later, file: own) == .wait)
        // A change of a user setting is written as usual, keeping that layout, which still
        // waits: Restart, or the launch, takes in only the layout, and the change stays.
        let toggled = settings(layouts, showOnHover: true, own: ["a": 0, "b": 1, "placed": 1])
        let changed = Policy.Local(settings: toggled, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.needsExchange(.localChange, local: changed))
        #expect(Policy.decide(.check, local: changed, file: own) == .write)
        #expect(Policy.decide(.localChange, local: changed, file: own) == .write)
        #expect(Policy.decide(.launch, local: changed, file: own) == .takeInLayout)
        #expect(Policy.hint(for: changed, version: ownVersion) == .restart)
        let rewritten = Policy.planWrite(toggled, file: written.settings, fileCurrentLayouts: Set(written.currentLayouts), fileCopiedLayouts: [], layouts: layouts, local: changed)
        #expect(isLayout(rewritten.settings[layouts.own], ["a": 5, "b": 1, "placed": 1]))
        #expect(rewritten.record.takesInLayout)
        var launched = state
        launched.recordLayoutTakeIn(layoutDigest: ownVersion.layoutDigest)
        let afterLaunch = Policy.Local(settings: toggled.merging(takenIn) { $1 }, layouts: layouts, state: launched, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(afterLaunch.hasChanges)
        #expect(Policy.decide(.localChange, local: afterLaunch, file: own) == .write)
        // After a layout change of the user's, keeping this Mac's settings writes its layout.
        var keepsEdited = keeps
        keepsEdited.editsLayout = true
        #expect(Policy.writesOwnLayout(keepsEdited))
        #expect(!Policy.takesInKeptLayout(fileLayoutDigest: remoteDigest, writtenLayoutDigest: writtenDigest, local: keepsEdited))
    }

    @Test("A kept layout this Mac has not taken in is taken in when this Mac joins again before a restart", arguments: layoutBackends)
    func keptLayoutTakenInAfterRejoin(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mineLayout: [String: Any] = ["a": 0, "b": 1]
        let otherLayout: [String: Any] = ["a": 2, "b": 1]
        // This Mac holds only holzBar's own layout; another Mac arranged `otherLayout`; each
        // changed a setting, and the user keeps this Mac's settings.
        let mine = settings(layouts, showOnHover: false, own: mineLayout)
        let remote = settings(layouts, showOnHover: true, own: otherLayout)
        var state = Policy.State(
            base: Policy.userDigest(of: settings(layouts).filter { $0.key != "ShowOnHover" }),
            baseLayoutDigest: Policy.layoutDigest(of: mine, layouts: layouts),
            lastSynced: lastSynced
        )
        var keeps = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: true)
        keeps.keepsOver = lastSynced.addingTimeInterval(60)
        #expect(Policy.decide(.localChange, local: keeps, file: version(remote, layouts)) == .write)
        let written = Policy.planWrite(mine, file: remote, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps)
        #expect(written.record.takesInLayout)
        let writeDate = lastSynced.addingTimeInterval(120)
        state.recordWrite(written.record, modified: writeDate, local: keeps)

        // Sync is turned off and on, or the same folder chosen again, before a restart.
        state.leaveFolder(forgetsLastSync: false)
        let joining = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let current = Policy.withoutStaleLayouts(written.settings, currentLayouts: Set(written.currentLayouts))
        let own = Policy.Version(settings: current, layouts: layouts, isFromThisMac: true, modified: writeDate, isNewer: false)
        for trigger in [Policy.Trigger.localChange, .check, .launch] {
            #expect(Policy.decide(trigger, local: joining, file: .version(own)) == .adopt)
        }
        // The joining Mac takes the kept layout in instead of recording it as synced.
        let takenIn = Policy.ownLayoutToTakeIn(current, over: mine, layouts: layouts, local: joining, version: own)
        #expect(isLayout(takenIn[layouts.own], otherLayout))
        state.recordAdoption(own, local: joining, takesInOwnLayout: !takenIn.isEmpty)
        #expect(state.baseLayoutDigest == Policy.layoutDigest(of: mine, layouts: layouts))
        #expect(state.pending == nil)

        // Restart, or the next launch, takes it in.
        let after = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: after, file: .version(own)) == .takeInLayout)
        #expect(Policy.decide(.launch, local: after, file: .version(own)) == .takeInLayout)
        #expect(Policy.hint(for: after, version: own) == .restart)
        #expect(isLayout(Policy.keptLayoutToTakeIn(current, over: mine, layouts: layouts)[layouts.own], otherLayout))
        // A drag before then asks instead of writing this Mac's layout over the other Mac's.
        let dragged = settings(layouts, showOnHover: false, own: ["a": 1, "b": 1])
        let edited = Policy.Local(settings: dragged, layouts: layouts, state: state, layoutEdits: 1, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: edited, file: .version(own)) == .ask)

        // A version of this Mac's own layout holds nothing to take in.
        let ownLayout = Policy.planWrite(mine, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: joining)
        let ownCurrent = Policy.withoutStaleLayouts(ownLayout.settings, currentLayouts: Set(ownLayout.currentLayouts))
        let ownVersion = Policy.Version(settings: ownCurrent, layouts: layouts, isFromThisMac: true, modified: writeDate, isNewer: false)
        #expect(Policy.ownLayoutToTakeIn(ownCurrent, over: mine, layouts: layouts, local: joining, version: ownVersion).isEmpty)
    }

    @Test("A write over a version that is not newer keeps its layout and takes it in", arguments: layoutBackends)
    func notNewerLayoutTakenIn(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let syncedSettings = settings(layouts, own: first)
        let mine = settings(layouts, showOnHover: false, own: first)
        let remote = settings(layouts, own: third)
        let changed = local(mine, layouts, base: syncedSettings)
        #expect(Policy.decide(.localChange, local: changed, file: version(remote, layouts, isNewer: false)) == .write)
        let written = Policy.fileToWrite(mine, file: remote, fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: Policy.writesOwnLayout(changed))
        #expect(isLayout(written.settings[layouts.own], ["a": 2, "c": 1, "b": 1]))
        let writtenDigest = Policy.syncedLayoutDigest(afterWriting: written.settings, currentLayouts: Set(written.currentLayouts), layouts: layouts, local: changed)
        #expect(Policy.takesInKeptLayout(fileLayoutDigest: Policy.layoutDigest(of: remote, layouts: layouts), writtenLayoutDigest: writtenDigest, local: changed))
        var state = Policy.State(base: changed.base, baseLayoutDigest: changed.baseLayoutDigest, lastSynced: lastSynced)
        state.recordWrite(Policy.WriteRecord(layoutDigest: writtenDigest, takesInLayout: true), modified: lastSynced, local: changed)
        let after = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.launch, local: after, file: ownVersion(written, layouts, modified: lastSynced)) == .takeInLayout)
        // Without the take-in, the write records the written layout.
        var plain = Policy.State(base: changed.base, baseLayoutDigest: changed.baseLayoutDigest, lastSynced: lastSynced)
        plain.recordWrite(Policy.WriteRecord(layoutDigest: writtenDigest, takesInLayout: false), modified: lastSynced, local: changed)
        #expect(plain.baseLayoutDigest == writtenDigest)
        #expect(plain.pending == nil)
    }

    @Test("A write that keeps the layout this Mac last synced takes nothing in", arguments: layoutBackends)
    func keptSyncedLayoutTakesNothingIn(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let syncedSettings = settings(layouts, own: first)
        // holzBar placed a new item and moved a known one since the last sync.
        let mine = settings(layouts, showOnHover: false, own: ["a": 2, "b": 1, "placed": 1])
        let changed = local(mine, layouts, base: syncedSettings)
        let written = Policy.fileToWrite(mine, file: syncedSettings, fileCurrentLayouts: [layouts.own], layouts: layouts, keepsOwnLayout: false)
        let writtenDigest = Policy.syncedLayoutDigest(afterWriting: written.settings, currentLayouts: Set(written.currentLayouts), layouts: layouts, local: changed)
        #expect(writtenDigest != changed.layoutDigest)
        #expect(writtenDigest != changed.baseLayoutDigest)
        let fileDigest = Policy.layoutDigest(of: syncedSettings, layouts: layouts)
        #expect(!Policy.takesInKeptLayout(fileLayoutDigest: fileDigest, writtenLayoutDigest: writtenDigest, local: changed))
        // Nor does a file without a current layout, or a write of this Mac's own.
        #expect(!Policy.takesInKeptLayout(fileLayoutDigest: nil, writtenLayoutDigest: changed.layoutDigest, local: changed))
        #expect(!Policy.takesInKeptLayout(fileLayoutDigest: Policy.layoutDigest(of: settings(layouts, own: third), layouts: layouts), writtenLayoutDigest: changed.layoutDigest, local: changed))
        // This Mac's own version with the layout it recorded holds nothing to take in.
        var state = Policy.State(base: changed.base, baseLayoutDigest: changed.baseLayoutDigest, lastSynced: lastSynced)
        state.recordWrite(Policy.WriteRecord(layoutDigest: writtenDigest, takesInLayout: false), modified: lastSynced, local: changed)
        let after = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        guard case .version(let own) = ownVersion(written, layouts, modified: lastSynced) else {
            Issue.record("Expected a version")
            return
        }
        #expect(!Policy.holdsLayoutToTakeIn(own, local: after))
        #expect(Policy.decide(.check, local: after, file: .version(own)) == .adopt)
        // Nor does a joining Mac's.
        let joining = local(mine, layouts, base: nil, baseLayout: settings(layouts, own: third))
        #expect(!Policy.holdsLayoutToTakeIn(own, local: joining))
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

    @Test("Restart asks instead while an arrangement on the bar is still to be saved", arguments: layoutBackends)
    func restartWaitsForUnsavedArrangement(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let synced = settings(layouts, own: first)
        let waiting = local(synced, layouts, base: synced, pending: lastSynced.addingTimeInterval(60))
        #expect(Policy.hint(for: waiting, savesLayoutSoon: false) == .restart)
        #expect(Policy.hint(for: waiting, savesLayoutSoon: true) == .choice(isJoining: false))
        let joining = local(synced, layouts, base: nil)
        #expect(Policy.hint(for: joining, savesLayoutSoon: true) == .choice(isJoining: true))
        let edited = local(synced, layouts, base: synced, editsLayout: true)
        #expect(Policy.hint(for: edited, savesLayoutSoon: false) == .choice(isJoining: false))
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

    @Test("A version another Mac wrote before this Mac's last sync asks instead of being written over", arguments: layoutBackends)
    func olderVersionFromAnotherMacAsks(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // Another Mac's version without a setting this Mac has: applying it leaves this Mac's
        // settings different from the version's.
        var mine = settings(layouts, own: first)
        mine["ShowOnClick"] = true
        let remote = settings(layouts, showOnHover: false, own: first)
        let applied = Policy.settingsToApply(remote, over: mine, layouts: layouts, baseLayoutDigest: nil, editsLayout: false)
        let afterApply = mine.merging(applied) { $1 }
        let appliedVersion = Policy.Version(settings: remote, layouts: layouts, isFromThisMac: false, modified: lastSynced, isNewer: true)
        var state = Policy.State(lastSynced: lastSynced.addingTimeInterval(-60))
        state.recordApplied(appliedVersion, base: Policy.userDigest(of: afterApply), layoutDigest: appliedVersion.layoutDigest)
        #expect(state.base != appliedVersion.userDigest)
        var seen = appliedVersion
        seen.isNewer = false
        // The version this Mac applied is synced: nothing to do, at no launch.
        let synced = Policy.Local(settings: afterApply, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: synced, file: .version(seen)) == .none)
        #expect(Policy.decide(.launch, local: synced, file: .version(seen)) == .none)

        // This Mac writes a change; the file then holds another Mac's change dated before it.
        var changedSettings = afterApply
        changedSettings["ShowOnClick"] = false
        let changed = Policy.Local(settings: changedSettings, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let written = Policy.planWrite(changedSettings, file: remote, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: changed)
        state.recordWrite(written.record, modified: lastSynced.addingTimeInterval(100), local: changed)
        var olderSettings = remote
        olderSettings["ShowOnHover"] = true
        let older = Policy.Version(settings: olderSettings, layouts: layouts, isFromThisMac: false, modified: lastSynced.addingTimeInterval(90), isNewer: false)
        let idle = Policy.Local(settings: changedSettings, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: idle, file: .version(older)) == .ask)
        #expect(Policy.decide(.launch, local: idle, file: .version(older)) == .ask)
        #expect(Policy.hint(for: idle, version: older) == .choice(isJoining: false))
        // This Mac's next change asks too, instead of writing over the other Mac's.
        var next = changedSettings
        next["ShowOnHover"] = false
        let nextLocal = Policy.Local(settings: next, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: nextLocal, file: .version(older)) == .ask)
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

    // MARK: Counting layout edits

    @Test("A layout from before the update counts as changed until the first sync only on a Mac that has not synced")
    func initialLayoutEdits() {
        #expect(Policy.initialLayoutEdits(hasLayout: true, syncs: false, hasSynced: false) == 1)
        #expect(Policy.initialLayoutEdits(hasLayout: true, syncs: true, hasSynced: true) == 0)
        // Sync on, but the folder was never in reach: the layout may be the user's.
        #expect(Policy.initialLayoutEdits(hasLayout: true, syncs: true, hasSynced: false) == 1)
        // Sync turned off after it synced: the layout may have changed since.
        #expect(Policy.initialLayoutEdits(hasLayout: true, syncs: false, hasSynced: true) == 1)
        for syncs in [false, true] {
            for hasSynced in [false, true] {
                #expect(Policy.initialLayoutEdits(hasLayout: false, syncs: syncs, hasSynced: hasSynced) == 0)
            }
        }
        #expect(Policy.editsLayout(count: Policy.initialLayoutEdits(hasLayout: true, syncs: true, hasSynced: false), synced: 0))
        #expect(!Policy.editsLayout(count: Policy.initialLayoutEdits(hasLayout: true, syncs: true, hasSynced: true), synced: 0))
        #expect(!Policy.editsLayout(count: Policy.initialLayoutEdits(hasLayout: false, syncs: false, hasSynced: false), synced: 0))
    }

    @Test("After the update, a Mac that syncs takes in the layout of another Mac of its macOS version without a question", arguments: layoutBackends)
    func upgradeOfSyncingMacTakesInLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // The first Mac updated wrote its layout; this Mac's differs by holzBar's own placement.
        let mine = settings(layouts, own: ["a": 0, "b": 1, "placed": 2])
        let remote = settings(layouts, own: ["a": 0, "b": 0], ownKnown: ["placed"])
        let edits = Policy.initialLayoutEdits(hasLayout: true, syncs: true, hasSynced: true)
        let joining = local(mine, layouts, base: nil, editsLayout: Policy.editsLayout(count: edits, synced: 0))
        for trigger in [Policy.Trigger.localChange, .check, .launch] {
            #expect(Policy.decide(trigger, local: joining, file: version(remote, layouts)) == .adopt)
        }
        let takenIn = Policy.ownLayoutToTakeIn(remote, over: mine, layouts: layouts, local: joining, version: newerVersion(remote, layouts))
        #expect(isLayout(takenIn[layouts.own], ["a": 0, "b": 0]))
        // A Mac that never synced, even with sync on, compares its layout once, as it may be
        // the user's.
        let unsynced = Policy.initialLayoutEdits(hasLayout: true, syncs: true, hasSynced: false)
        let joiningUnsynced = local(mine, layouts, base: nil, editsLayout: Policy.editsLayout(count: unsynced, synced: 0))
        #expect(Policy.decide(.check, local: joiningUnsynced, file: version(remote, layouts)) == .ask)
    }

    @Test("Only layout edits the last sync did not record count")
    func editsLayoutCount() {
        #expect(!Policy.editsLayout(count: 0, synced: 0))
        #expect(!Policy.editsLayout(count: 3, synced: 3))
        #expect(Policy.editsLayout(count: 4, synced: 3))
        #expect(Policy.editsLayout(count: 3, synced: 4))
    }

    @Test("Saving a layout counts as a change of the user's only when the user arranged it and it changed")
    func layoutSaveCountsOnlyWhenChanged() {
        let before = ["a": 0, "b": 1]
        // A Command-click on the bar that moved nothing saves the same layout.
        #expect(!Policy.countsAsLayoutEdit(byUser: true, saved: before, before: before))
        #expect(Policy.countsAsLayoutEdit(byUser: true, saved: ["a": 0, "b": 2], before: before))
        #expect(Policy.countsAsLayoutEdit(byUser: true, saved: ["a": 0, "b": 1, "c": 2], before: before))
        // holzBar's own placements never count.
        #expect(!Policy.countsAsLayoutEdit(byUser: false, saved: ["a": 0, "b": 2], before: before))
    }

    @Test("Before macOS 27, saving the bar counts as a change of the user's only when an item's saved section changed")
    func sectionSaveCountsOnlyChangedSections() {
        let before = ["a": 0, "b": 1]
        // A Command-click that moved nothing, with an item saved for the first time where
        // macOS put it.
        #expect(!Policy.countsAsSectionSaveEdit(byUser: true, saved: ["a": 0, "b": 1, "new": 0], before: before))
        #expect(!Policy.countsAsSectionSaveEdit(byUser: true, saved: before, before: before))
        // A move of the user's.
        #expect(Policy.countsAsSectionSaveEdit(byUser: true, saved: ["a": 0, "b": 2], before: before))
        #expect(Policy.countsAsSectionSaveEdit(byUser: true, saved: ["a": 1, "b": 1, "new": 0], before: before))
        // holzBar's own saves never count.
        #expect(!Policy.countsAsSectionSaveEdit(byUser: false, saved: ["a": 0, "b": 2], before: before))
        #expect(!Policy.countsAsSectionSaveEdit(byUser: true, saved: [String: Int](), before: [String: Int]()))
    }

    // MARK: Sync state

    @Test("A sync records the layout edits its decision saw, so an edit made while it ran still counts")
    func syncRecordsCapturedEdits() {
        var state = Policy.State(base: nil, layoutEdits: 4, syncedLayoutEdits: 3)
        #expect(state.editsLayout)
        // The exchange starts with the count it sees; the user edits while it runs.
        let captured = state.layoutEdits
        state.countLayoutEdit()
        #expect(state.layoutEdits == 5)
        state.markSynced(base: "base", layout: "layout", layoutEdits: captured, modified: nil)
        #expect(state.syncedLayoutEdits == 4)
        #expect(state.editsLayout)
        // Without an edit in between, the sync leaves no edit.
        state.markSynced(base: "base", layout: "layout", layoutEdits: state.layoutEdits, modified: nil)
        #expect(!state.editsLayout)
    }

    @Test("The layout edit count wraps instead of trapping")
    func layoutEditCountWraps() {
        var state = Policy.State(layoutEdits: Int.max, syncedLayoutEdits: Int.max)
        #expect(!state.editsLayout)
        state.countLayoutEdit()
        #expect(state.layoutEdits == Int.min)
        #expect(state.editsLayout)
    }

    @Test("A sync records the base, the layout, the newest date and that nothing waits")
    func markSynced() {
        let older = lastSynced.addingTimeInterval(-60)
        let newer = lastSynced.addingTimeInterval(60)
        var state = Policy.State(base: nil, baseLayoutDigest: "old", lastSynced: lastSynced, pending: newer)
        state.markSynced(base: "base", layout: nil, layoutEdits: 2, modified: older)
        #expect(state.base == "base")
        #expect(state.baseLayoutDigest == Policy.noLayoutDigest)
        #expect(state.syncedLayoutEdits == 2)
        // A version dated before the last sync never moves it back.
        #expect(state.lastSynced == lastSynced)
        #expect(state.pending == nil)
        state.markSynced(base: "next", layout: "layout", layoutEdits: 2, modified: newer)
        #expect(state.baseLayoutDigest == "layout")
        #expect(state.lastSynced == newer)
        state.markSynced(base: "next", layout: "layout", layoutEdits: 2, modified: nil)
        #expect(state.lastSynced == newer)
    }

    @Test("Adopting records the version's layout, or this Mac's while the version's layout waits for a restart", arguments: layoutBackends)
    func recordAdoption(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: ["a": 0, "known": 2, "unseen": 1])
        let remote = settings(layouts, own: ["a": 1], ownKnown: ["known"])
        let modified = lastSynced.addingTimeInterval(60)
        let joining = local(mine, layouts, base: nil)
        let remoteLayout = Policy.layoutDigest(of: remote, layouts: layouts)

        var adopted = Policy.State(lastSynced: lastSynced)
        let remoteVersion = Policy.Version(settings: remote, layouts: layouts, isFromThisMac: false, modified: modified, isNewer: true)
        #expect(remoteVersion.layoutDigest == remoteLayout)
        adopted.recordAdoption(remoteVersion, local: joining, takesInOwnLayout: false)
        #expect(adopted.base == joining.userDigest)
        #expect(adopted.baseLayoutDigest == remoteLayout)
        #expect(adopted.lastSynced == modified)
        #expect(adopted.pending == nil)

        var waiting = Policy.State(lastSynced: lastSynced)
        waiting.recordAdoption(remoteVersion, local: joining, takesInOwnLayout: true)
        #expect(waiting.base == joining.userDigest)
        #expect(waiting.baseLayoutDigest == joining.layoutDigest)
        #expect(waiting.lastSynced == lastSynced)
        #expect(waiting.pending == modified)
        // The version stays newer and is applied, by Restart or at the next launch, with
        // the layout taken in; its hint is a restart.
        let after = Policy.Local(settings: mine, layouts: layouts, state: waiting, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let file = Policy.File.version(
            Policy.Version(settings: remote, layouts: layouts, isFromThisMac: false, modified: modified, isNewer: modified > lastSynced)
        )
        #expect(Policy.decide(.check, local: after, file: file) == .apply)
        #expect(Policy.decide(.launch, local: after, file: file) == .apply)
        #expect(Policy.hint(for: after) == .restart)
        let applied = Policy.settingsToApply(remote, over: mine, layouts: layouts, baseLayoutDigest: after.baseLayoutDigest, editsLayout: after.editsLayout)
        #expect(isLayout(applied[layouts.own], ["a": 1, "unseen": 1]))
        // Recording the version's layout instead would have left this Mac's layout in place.
        let adoptedLocal = Policy.Local(settings: mine, layouts: layouts, state: adopted, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: adoptedLocal, file: file) == .adopt)
    }

    @Test("A Mac that synced keeps holzBar's own placements when another Mac changed only the other macOS version's layout", arguments: layoutBackends)
    func placementsKeptWhenOtherLayoutChanges(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // Synced with `first`; holzBar placed an item since.
        let mine = settings(layouts, own: ["a": 0, "b": 1, "placed": 1], other: second)
        let synced = local(mine, layouts, base: mine, baseLayout: settings(layouts, own: first))
        #expect(synced.layoutDigest != synced.baseLayoutDigest)
        #expect(!synced.hasChanges)
        let remote = version(settings(layouts, own: first, other: third), layouts)
        #expect(Policy.decide(.check, local: synced, file: remote) == .adopt)
        #expect(Policy.decide(.launch, local: synced, file: remote) == .adopt)
        #expect(Policy.decide(.localChange, local: synced, file: remote) == .adopt)
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
