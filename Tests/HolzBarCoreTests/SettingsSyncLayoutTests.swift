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
        // it is no arrangement to ask about. This Mac passes it on as a copy, as its own
        // layout may be older than the arrangement the copy stands for, and writes its own
        // layout over it after a layout change of the user's.
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
        let passedOn = Policy.fileToWrite(
            mine,
            file: copy,
            fileCurrentLayouts: [layouts.other],
            fileCopiedLayouts: [layouts.own],
            layouts: layouts,
            keepsOwnLayout: false
        )
        #expect(isLayout(passedOn.settings[layouts.own], second))
        #expect(passedOn.currentLayouts == [layouts.other])
        #expect(passedOn.copiedLayouts == [layouts.own])
        let overCopy = Policy.fileToWrite(
            mine,
            file: copy,
            fileCurrentLayouts: [layouts.other],
            fileCopiedLayouts: [layouts.own],
            layouts: layouts,
            keepsOwnLayout: true
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
        if case .version(let answered) = earlierVersion(beta1File, layouts) {
            keeps.keepsOver = answered
        }
        #expect(Policy.decide(.localChange, local: keeps, file: earlierVersion(beta1File, layouts)) == .write)
        let kept = Policy.fileToWrite(moved, file: beta1File, fileCurrentLayouts: [], layouts: layouts, keepsOwnLayout: true)
        #expect(isLayout(kept.settings[layouts.own], second))
        #expect(kept.currentLayouts.contains(layouts.own))
        // Without a layout change of the user's, nothing asks.
        let unchanged = local(settings(layouts, showOnHover: false, own: second), layouts, base: settings(layouts), baseLayout: settings(layouts))
        #expect(Policy.decide(.localChange, local: unchanged, file: earlierVersion(beta1File, layouts)) == .write)
    }

    @Test("An old copy of this Mac's layout that a Mac still on 0.0.7 beta 1 writes back is passed on, and a drag writes over it without a question", arguments: layoutBackends)
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

        // A change of a user setting passes it on unchanged and unlisted: it may as well be a
        // beta 1 Mac's return to that arrangement, which that Mac would lose at its next
        // launch. The copy stays recognized.
        let changed = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let written = Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: changed)
        #expect(isLayout(written.settings[layouts.own], oldLayout))
        #expect(!written.currentLayouts.contains(layouts.own))
        #expect(!written.copiedLayouts.contains(layouts.own))
        #expect(written.record.oldCopyDigest == Policy.layoutDigest(of: [layouts.own: oldLayout], layouts: layouts))
        // A drag writes this Mac's layout over it, listed.
        var draggedLocal = changed
        draggedLocal.editsLayout = true
        let overCopy = Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: draggedLocal)
        #expect(isLayout(overCopy.settings[layouts.own], currentLayout))
        #expect(overCopy.currentLayouts.contains(layouts.own))
        #expect(overCopy.record.layoutDigest == Policy.layoutDigest(of: mine, layouts: layouts))

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

    @Test("An old copy of this Mac's layout stays recognized after the user rearranged many times", arguments: layoutBackends)
    func oldCopyRecognizedAfterManyEdits(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: first)
        var state = Policy.State(base: Policy.userDigest(of: mine), baseLayoutDigest: nil, lastSynced: lastSynced, versionDigest: Policy.userDigest(of: mine))
        // This Mac wrote `first`; a Mac still on beta 1 applied it. The user then rearranged
        // twenty times, each written.
        let edits = 20
        for index in 0 ... edits {
            let arranged = settings(layouts, own: ["a": index, "b": 1])
            state.countLayoutEdit()
            let local = Policy.Local(settings: arranged, layouts: layouts, state: state, layoutEdits: state.layoutEdits, postponed: nil, forcesWrite: false)
            state.recordWrite(Policy.WriteRecord(layoutDigest: local.layoutDigest, takesInLayout: false), modified: lastSynced.addingTimeInterval(Double(index)), local: local)
        }
        // The beta 1 Mac writes its copy of `first` back, unlisted; the next drag writes over it
        // without a question.
        let beta1File = settings(layouts, own: first)
        state.countLayoutEdit()
        let dragged = Policy.Local(settings: settings(layouts, own: ["a": 99, "b": 1]), layouts: layouts, state: state, layoutEdits: state.layoutEdits, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: dragged, file: earlierVersion(beta1File, layouts)) == .write)
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
        keeps.keepsOver = newerVersion(remote, layouts)
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
        keeps.keepsOver = newerVersion(remote, layouts)
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

    @Test("A layout change of the user's before this Mac joins again asks instead of writing over a kept layout", arguments: layoutBackends)
    func keptLayoutAsksAfterEditAndRejoin(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mineLayout: [String: Any] = ["a": 0, "b": 1]
        let otherLayout: [String: Any] = ["a": 2, "b": 1]
        let mine = settings(layouts, showOnHover: false, own: mineLayout)
        let remote = settings(layouts, showOnHover: true, own: otherLayout)
        var state = Policy.State(
            base: Policy.userDigest(of: settings(layouts).filter { $0.key != "ShowOnHover" }),
            baseLayoutDigest: Policy.layoutDigest(of: mine, layouts: layouts),
            lastSynced: lastSynced
        )
        // The user keeps this Mac's settings without rearranging: the write keeps the other
        // Mac's arrangement, which waits to be taken in.
        var keeps = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: true)
        keeps.keepsOver = newerVersion(remote, layouts)
        let written = Policy.planWrite(mine, file: remote, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps)
        #expect(written.record.takesInLayout)
        let writeDate = lastSynced.addingTimeInterval(120)
        state.recordWrite(written.record, modified: writeDate, local: keeps)
        let own = Policy.Version(
            settings: Policy.withoutStaleLayouts(written.settings, currentLayouts: Set(written.currentLayouts)),
            layouts: layouts,
            isFromThisMac: true,
            modified: writeDate,
            isNewer: false
        )
        // Before a restart the user rearranges the bar or the Layout pane.
        state.countLayoutEdit()
        let dragged = settings(layouts, showOnHover: false, own: ["a": 1, "b": 0])
        for forgetsLastSync in [false, true] {
            // Sync is turned off and on, or the same folder chosen again.
            var rejoined = state
            rejoined.leaveFolder(forgetsLastSync: forgetsLastSync)
            let joining = Policy.Local(settings: dragged, layouts: layouts, state: rejoined, layoutEdits: rejoined.layoutEdits, postponed: nil, forcesWrite: false)
            #expect(joining.isJoining && joining.editsLayout)
            for trigger in [Policy.Trigger.localChange, .check, .launch] {
                #expect(Policy.decide(trigger, local: joining, file: .version(own)) == .ask)
            }
            #expect(Policy.hint(for: joining, version: own) == .choice(isJoining: true))
            // "Later" waits for that version.
            var later = joining
            later.postponed = writeDate
            #expect(Policy.decide(.check, local: later, file: .version(own)) == .wait)
            // Without the layout change, a joining Mac with other changes takes the kept layout
            // in at launch, and writes those changes while it runs, keeping that layout.
            let toggled = settings(layouts, showOnHover: true, own: mineLayout)
            let unedited = Policy.Local(settings: toggled, layouts: layouts, state: rejoined, layoutEdits: rejoined.syncedLayoutEdits, postponed: nil, forcesWrite: false)
            #expect(Policy.decide(.launch, local: unedited, file: .version(own)) == .takeInLayout)
            #expect(Policy.decide(.localChange, local: unedited, file: .version(own)) == .write)
            #expect(Policy.planWrite(toggled, file: written.settings, fileCurrentLayouts: Set(written.currentLayouts), fileCopiedLayouts: [], layouts: layouts, local: unedited).record.takesInLayout)
            // A version of this Mac's own layout, which holds nothing of another Mac's, is
            // written over.
            let ownLayout = Policy.planWrite(mine, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: joining)
            let plain = Policy.Version(
                settings: Policy.withoutStaleLayouts(ownLayout.settings, currentLayouts: Set(ownLayout.currentLayouts)),
                layouts: layouts,
                isFromThisMac: true,
                modified: writeDate,
                isNewer: false
            )
            #expect(Policy.decide(.localChange, local: joining, file: .version(plain)) == .write)
            // So is an old version of this Mac's own with a layout that is not the kept one.
            let stale = Policy.Version(settings: settings(layouts, own: third), layouts: layouts, isFromThisMac: true, modified: writeDate, isNewer: false)
            #expect(Policy.decide(.localChange, local: joining, file: .version(stale)) == .write)
        }
    }

    @Test("An older version of this Mac's own that a sync app brings back is never taken in, and a write replaces its layout", arguments: layoutBackends)
    func oldOwnVersionNotTakenIn(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let olderLayout: [String: Any] = ["a": 0, "b": 1]
        let currentLayout: [String: Any] = ["a": 2, "b": 0]
        // This Mac synced `currentLayout`; holzBar placed an item since.
        let mine = settings(layouts, own: currentLayout.merging(["placed": 1]) { $1 })
        let synced = settings(layouts, own: currentLayout)
        let state = Policy.State(
            base: Policy.userDigest(of: synced),
            baseLayoutDigest: Policy.layoutDigest(of: synced, layouts: layouts),
            lastSynced: lastSynced,
            versionDigest: Policy.userDigest(of: synced)
        )
        // The sync app puts this Mac's older upload back.
        let older = settings(layouts, own: olderLayout)
        let olderVersion = Policy.Version(settings: older, layouts: layouts, isFromThisMac: true, modified: lastSynced.addingTimeInterval(-60), isNewer: false)
        let idle = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.isOldOwnLayout(olderVersion, local: idle))
        #expect(!Policy.holdsLayoutToTakeIn(olderVersion, local: idle))
        for trigger in [Policy.Trigger.launch, .check, .localChange] {
            #expect(Policy.decide(trigger, local: idle, file: .version(olderVersion)) == .none)
        }
        // A change of this Mac's is written with this Mac's layout, not the old copy, and
        // nothing waits to be taken in.
        let toggled = settings(layouts, showOnHover: false, own: currentLayout.merging(["placed": 1]) { $1 })
        let changed = Policy.Local(settings: toggled, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: changed, file: .version(olderVersion)) == .write)
        #expect(Policy.decide(.launch, local: changed, file: .version(olderVersion)) == .none)
        let push = Policy.planWrite(toggled, file: older, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: olderVersion, layouts: layouts, local: changed)
        #expect(isLayout(push.settings[layouts.own], toggled[layouts.own] as? [String: Any] ?? [:]))
        #expect(push.currentLayouts.contains(layouts.own))
        #expect(push.record == Policy.WriteRecord(layoutDigest: changed.layoutDigest, takesInLayout: false))
        // Another Mac's version with that layout is no copy of this Mac's: its arrangement is
        // kept.
        var olderFromOther = olderVersion
        olderFromOther.isFromThisMac = false
        let fromOther = Policy.planWrite(toggled, file: older, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: olderFromOther, layouts: layouts, local: changed)
        #expect(isLayout(fromOther.settings[layouts.own], olderLayout.merging(["placed": 1]) { $1 }))

        // The layout this Mac last synced, and a kept one, are no old copies.
        var atBase = olderVersion
        atBase.layoutDigest = idle.baseLayoutDigest
        #expect(!Policy.isOldOwnLayout(atBase, local: idle))
        var keeping = changed
        keeping.keptLayoutDigest = olderVersion.layoutDigest
        #expect(!Policy.isOldOwnLayout(olderVersion, local: keeping))
        let kept = Policy.planWrite(toggled, file: older, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: olderVersion, layouts: layouts, local: keeping)
        #expect(kept.record.takesInLayout)
        #expect(isLayout(kept.settings[layouts.own], olderLayout.merging(["placed": 1]) { $1 }))
        // Nor is the folder's arrangement while this Mac joins, which it takes in.
        var joiningState = state
        joiningState.leaveFolder(forgetsLastSync: false)
        let joining = Policy.Local(settings: toggled, layouts: layouts, state: joiningState, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(!Policy.isOldOwnLayout(olderVersion, local: joining))
        #expect(Policy.planWrite(toggled, file: older, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: olderVersion, layouts: layouts, local: joining).record.takesInLayout)
        var noLayout = olderVersion
        noLayout.layoutDigest = nil
        #expect(!Policy.isOldOwnLayout(noLayout, local: idle))

        // This Mac's last version, not older than its last sync, holds another Mac's layout
        // whose record was lost (sync turned off while the write ran, or a quit right after
        // it): it is no old copy. A change keeps that layout and takes it in later.
        let latest = Policy.Version(settings: older, layouts: layouts, isFromThisMac: true, modified: lastSynced.addingTimeInterval(0.5), isNewer: false)
        #expect(!Policy.isOldOwnLayout(latest, local: changed))
        let overLatest = Policy.planWrite(toggled, file: older, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: latest, layouts: layouts, local: changed)
        #expect(isLayout(overLatest.settings[layouts.own], olderLayout.merging(["placed": 1]) { $1 }))
        #expect(overLatest.record.takesInLayout)
        var later = latest
        later.modified = lastSynced.addingTimeInterval(30)
        #expect(!Policy.isOldOwnLayout(later, local: changed))
    }

    @Test("A kept layout that a Mac still on 0.0.7 beta 1 writes back is passed on, never replaced by holzBar's own layout", arguments: layoutBackends)
    func keptLayoutWrittenBackByBeta1(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mineLayout: [String: Any] = ["a": 0, "b": 1]
        let otherLayout: [String: Any] = ["a": 2, "b": 1]
        // This Mac holds only holzBar's own layout; another Mac arranged `otherLayout`; the user
        // keeps this Mac's settings without rearranging.
        let mine = settings(layouts, showOnHover: false, own: mineLayout)
        let remote = settings(layouts, showOnHover: true, own: otherLayout)
        var state = Policy.State(
            base: Policy.userDigest(of: settings(layouts).filter { $0.key != "ShowOnHover" }),
            baseLayoutDigest: Policy.layoutDigest(of: mine, layouts: layouts),
            lastSynced: lastSynced
        )
        var keeps = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: true)
        keeps.keepsOver = newerVersion(remote, layouts)
        let written = Policy.planWrite(mine, file: remote, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps)
        #expect(written.record.takesInLayout)
        state.recordWrite(written.record, modified: lastSynced.addingTimeInterval(120), local: keeps)
        // The kept layout is the other Mac's arrangement, not one this Mac synced.
        #expect(!state.recentLayouts.contains(Policy.layoutDigest(of: remote, layouts: layouts)))

        // A Mac of this macOS version still on beta 1 applies the written file at launch and
        // writes it back without listing its layouts.
        let beta1File = written.settings
        let beta1Version = Policy.Version(
            settings: Policy.withoutStaleLayouts(beta1File, currentLayouts: []),
            layouts: layouts,
            isFromThisMac: false,
            modified: lastSynced.addingTimeInterval(200),
            isNewer: true,
            unlistedLayoutDigest: Policy.unlistedLayoutDigest(in: beta1File, currentLayouts: [], layouts: layouts)
        )
        let idle = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: idle, file: .version(beta1Version)) == .adopt)
        state.recordAdoption(beta1Version, local: idle, takesInOwnLayout: false)

        // A change of a user setting is written; the other Mac's arrangement is passed on as
        // it is, unlisted, and holzBar's own layout does not replace it (SA-05).
        let toggled = settings(layouts, showOnHover: true, own: mineLayout)
        let changed = Policy.Local(settings: toggled, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: changed, file: .version(beta1Version)) == .write)
        let push = Policy.planWrite(toggled, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: changed)
        #expect(isLayout(push.settings[layouts.own], otherLayout))
        #expect(!push.currentLayouts.contains(layouts.own))
        // A layout change of the user's asks before it replaces that arrangement.
        let edited = Policy.Local(settings: settings(layouts, showOnHover: false, own: ["a": 1, "b": 0]), layouts: layouts, state: state, layoutEdits: 1, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: edited, file: .version(beta1Version)) == .ask)
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

    // MARK: The other macOS version's layout from an older version

    @Test("A stale layout of the other macOS version from an older version is neither taken in nor passed on as current, so the other Mac keeps its arrangement", arguments: layoutBackends)
    func staleOtherLayoutPassedOnAsCopy(backend: MenuBarBackendKind) {
        // Mac A runs `backend`; Mac C runs the other macOS version.
        let layouts = Policy.Layouts(backend: backend)
        let otherLayouts = Policy.Layouts(backend: backend == .accessibility27 ? .service26 : .accessibility27)
        let mineLayout: [String: Any] = ["a": 0, "b": 1]
        let staleOther: [String: Any] = ["x": 0, "y": 1]
        let currentOther: [String: Any] = ["x": 1, "y": 0]
        // A wrote V1, holding C's arrangement `staleOther` as current.
        let v1Settings = settings(layouts, own: mineLayout, other: staleOther)
        var stateA = Policy.State(
            base: Policy.userDigest(of: v1Settings),
            baseLayoutDigest: Policy.layoutDigest(of: v1Settings, layouts: layouts),
            lastSynced: lastSynced,
            versionDigest: Policy.userDigest(of: v1Settings)
        )
        // C rearranged and wrote V2; A adopts it, as only C's layout changed.
        let v2Settings = settings(layouts, own: mineLayout, other: currentOther)
        let v2 = Policy.Version(settings: v2Settings, layouts: layouts, isFromThisMac: false, modified: lastSynced.addingTimeInterval(120), isNewer: true)
        let beforeV2 = Policy.Local(settings: v1Settings, layouts: layouts, state: stateA, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: beforeV2, file: .version(v2)) == .adopt)
        #expect(Policy.takesInOtherLayout(from: v2, local: beforeV2))
        stateA = Policy.outcome(of: .adopt, isCheck: true, version: v2, local: beforeV2, state: stateA).state
        #expect(stateA.lastSynced == v2.modified)

        // The sync app brings V1 back: A takes nothing of it in, at launch or as it adopts it.
        let v1 = Policy.Version(settings: v1Settings, layouts: layouts, isFromThisMac: true, modified: lastSynced, isNewer: false)
        let mineA = settings(layouts, own: mineLayout, other: currentOther)
        let idleA = Policy.Local(settings: mineA, layouts: layouts, state: stateA, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.isBeforeLastSync(v1, local: idleA))
        #expect(!Policy.takesInOtherLayout(from: v1, local: idleA))
        #expect(Policy.decide(.launch, local: idleA, file: .version(v1)) == .adopt)
        #expect(Policy.takesInOtherLayout(from: v2, local: idleA))

        // A's next change writes V1's layout of C's macOS version as a copy, not as current.
        let toggledA = settings(layouts, showOnHover: false, own: mineLayout, other: currentOther)
        let changedA = Policy.Local(settings: toggledA, layouts: layouts, state: stateA, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: changedA, file: .version(v1)) == .write)
        let plan = Policy.planWrite(
            toggledA,
            file: v1Settings,
            fileCurrentLayouts: [layouts.own, layouts.other],
            fileCopiedLayouts: [],
            fileVersion: v1,
            layouts: layouts,
            local: changedA
        )
        #expect(plan.passesOtherAsCopy)
        #expect(!plan.currentLayouts.contains(layouts.other))
        #expect(plan.copiedLayouts.contains(layouts.other))
        #expect(plan.currentLayouts.contains(layouts.own))
        // The plan says so only when it passed a current layout of the other macOS version on:
        // not for an older version without one, one that lists it without holding it, or one
        // that holds it only as a copy.
        let withoutOther = settings(layouts, own: mineLayout)
        for (file, current, copied) in [
            (withoutOther, [layouts.own], [String]()),
            (withoutOther, [layouts.own, layouts.other], []),
            (v1Settings, [layouts.own], [layouts.other]),
        ] {
            let passed = Policy.planWrite(
                toggledA,
                file: file,
                fileCurrentLayouts: Set(current),
                fileCopiedLayouts: Set(copied),
                fileVersion: v1,
                layouts: layouts,
                local: changedA
            )
            #expect(!passed.passesOtherAsCopy)
            #expect(!passed.currentLayouts.contains(layouts.other))
        }

        // C applies A's change and keeps its arrangement.
        let mineC = settings(otherLayouts, own: currentOther, other: mineLayout)
        let stateC = Policy.State(
            base: Policy.userDigest(of: mineC),
            baseLayoutDigest: Policy.layoutDigest(of: mineC, layouts: otherLayouts),
            lastSynced: v2.modified,
            versionDigest: Policy.userDigest(of: mineC)
        )
        let idleC = Policy.Local(settings: mineC, layouts: otherLayouts, state: stateC, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let readByC = Policy.withoutStaleLayouts(plan.settings, currentLayouts: Set(plan.currentLayouts))
        let v3 = Policy.Version(settings: readByC, layouts: otherLayouts, isFromThisMac: false, modified: lastSynced.addingTimeInterval(300), isNewer: true)
        #expect(Policy.decide(.launch, local: idleC, file: .version(v3)) == .apply)
        let applied = Policy.settingsToApply(readByC, over: mineC, layouts: otherLayouts, baseLayoutDigest: idleC.baseLayoutDigest, editsLayout: false)
        #expect(applied[otherLayouts.own] == nil)
        #expect(applied["ShowOnHover"] as? Bool == false)
        // Listed as current, C would have applied the stale arrangement.
        let listed = Policy.withoutStaleLayouts(plan.settings, currentLayouts: Set(plan.currentLayouts).union([layouts.other]))
        let staleApplied = Policy.settingsToApply(listed, over: mineC, layouts: otherLayouts, baseLayoutDigest: idleC.baseLayoutDigest, editsLayout: false)
        #expect(isLayout(staleApplied[otherLayouts.own], staleOther))

        // An earlier upload of another Mac, dated before A's last sync, is passed on the same way.
        let earlier = Policy.Version(settings: v1Settings, layouts: layouts, isFromThisMac: false, modified: lastSynced.addingTimeInterval(60), isNewer: false)
        #expect(Policy.decide(.localChange, local: changedA, file: .version(earlier)) == .write)
        #expect(!Policy.takesInOtherLayout(from: earlier, local: idleA))
        let overEarlier = Policy.planWrite(toggledA, file: v1Settings, fileCurrentLayouts: [layouts.own, layouts.other], fileCopiedLayouts: [], fileVersion: earlier, layouts: layouts, local: changedA)
        #expect(overEarlier.copiedLayouts.contains(layouts.other))

        // A version as new as the last sync, in whole seconds, keeps it current.
        let same = Policy.Version(settings: v2Settings, layouts: layouts, isFromThisMac: true, modified: v2.modified, isNewer: false)
        var subsecond = changedA
        subsecond.lastSynced = v2.modified.addingTimeInterval(0.7)
        #expect(!Policy.isBeforeLastSync(same, local: subsecond))
        let overV2 = Policy.planWrite(toggledA, file: v2Settings, fileCurrentLayouts: [layouts.own, layouts.other], fileCopiedLayouts: [], fileVersion: v2, layouts: layouts, local: changedA)
        #expect(!overV2.passesOtherAsCopy)
        #expect(overV2.currentLayouts.contains(layouts.other))
        // Without a last sync, nothing is known to be older.
        var unsynced = changedA
        unsynced.lastSynced = nil
        #expect(!Policy.isBeforeLastSync(v1, local: unsynced))
        #expect(!Policy.passesOtherLayoutAsCopy(nil, local: changedA))
    }

    @Test("A copy of a macOS version's layout is never listed as current by a Mac of that version without a layout change of the user's, so a Mac behind never reverts the newest arrangement", arguments: layoutBackends)
    func copiedLayoutNotRelistedByMacBehind(backend: MenuBarBackendKind) {
        // Mac A runs `backend`; Macs C and D run the other macOS version. D was asleep and still
        // holds the old arrangement `oldC`; C arranged `midC`, then `newC`.
        let layoutsA = Policy.Layouts(backend: backend)
        let layoutsC = Policy.Layouts(backend: backend == .accessibility27 ? .service26 : .accessibility27)
        let mineLayout: [String: Any] = ["a": 0, "b": 1]
        let oldC: [String: Any] = ["x": 0, "y": 1]
        let midC: [String: Any] = ["x": 2, "y": 1]
        let newC: [String: Any] = ["x": 1, "y": 0]
        let mineA = settings(layoutsA, showOnHover: false, own: mineLayout, other: midC)

        /// A's version as D, then C, read it: D applies it and keeps `oldC`, then writes a change
        /// of its own over it; C, idle, reads D's version.
        func passOn(_ planA: Policy.WritePlan, copy: [String: Any], c stateC: Policy.State) -> Policy.Action {
            let readByD = Policy.withoutStaleLayouts(planA.settings, currentLayouts: Set(planA.currentLayouts))
            let mineD = settings(layoutsC, own: oldC, other: mineLayout)
            var stateD = Policy.State(
                base: Policy.userDigest(of: mineD),
                baseLayoutDigest: Policy.layoutDigest(of: mineD, layouts: layoutsC),
                lastSynced: lastSynced,
                versionDigest: Policy.userDigest(of: mineD)
            )
            let modifiedA = lastSynced.addingTimeInterval(600)
            var forD = Policy.Version(settings: readByD, layouts: layoutsC, isFromThisMac: false, modified: modifiedA, isNewer: true)
            let idleD = Policy.Local(settings: mineD, layouts: layoutsC, state: stateD, layoutEdits: 0, postponed: nil, forcesWrite: false)
            #expect(forD.layoutDigest == nil)
            #expect(Policy.decide(.launch, local: idleD, file: .version(forD)) == .apply)
            let appliedByD = Policy.settingsToApply(readByD, over: mineD, layouts: layoutsC, baseLayoutDigest: idleD.baseLayoutDigest, editsLayout: false)
            #expect(appliedByD[layoutsC.own] == nil)
            var settingsD = mineD.merging(appliedByD) { $1 }
            stateD.recordApplied(forD, base: Policy.userDigest(of: settingsD), layoutDigest: forD.layoutDigest)
            // D's user changes a setting; D writes over A's version.
            settingsD["ShowOnClick"] = false
            forD.isNewer = false
            let changedD = Policy.Local(settings: settingsD, layouts: layoutsC, state: stateD, layoutEdits: 0, postponed: nil, forcesWrite: false)
            #expect(Policy.decide(.localChange, local: changedD, file: .version(forD)) == .write)
            let planD = Policy.planWrite(
                settingsD,
                file: planA.settings,
                fileCurrentLayouts: Set(planA.currentLayouts),
                fileCopiedLayouts: Set(planA.copiedLayouts),
                fileVersion: forD,
                layouts: layoutsC,
                local: changedD
            )
            #expect(!planD.currentLayouts.contains(layoutsC.own))
            #expect(planD.copiedLayouts.contains(layoutsC.own))
            #expect(isLayout(planD.settings[layoutsC.own], copy))
            // C keeps its arrangement, whatever it decides.
            let mineC = settings(layoutsC, own: newC, other: mineLayout)
            let idleC = Policy.Local(settings: mineC, layouts: layoutsC, state: stateC, layoutEdits: 0, postponed: nil, forcesWrite: false)
            let readByC = Policy.withoutStaleLayouts(planD.settings, currentLayouts: Set(planD.currentLayouts))
            let forC = Policy.Version(settings: readByC, layouts: layoutsC, isFromThisMac: false, modified: modifiedA.addingTimeInterval(100), isNewer: true)
            let action = Policy.decide(.launch, local: idleC, file: .version(forC))
            let appliedByC = Policy.settingsToApplyAtLaunch(for: action, remote: readByC, over: mineC, layouts: layoutsC, local: idleC, version: forC)
            #expect(appliedByC[layoutsC.own] == nil)
            return action
        }
        func stateC(written: Date) -> Policy.State {
            let mineC = settings(layoutsC, own: newC, other: mineLayout)
            return Policy.State(
                base: Policy.userDigest(of: mineC),
                baseLayoutDigest: Policy.layoutDigest(of: mineC, layouts: layoutsC),
                lastSynced: written,
                versionDigest: Policy.userDigest(of: mineC),
                lastWritten: written
            )
        }

        // (a) C wrote `newC` concurrently with A's change, and the sync app kept C's version,
        // dated before A's: A asks, the user keeps A's settings, and C's newest arrangement is
        // passed on as a copy.
        let concurrentC = lastSynced.addingTimeInterval(400)
        let writtenA = lastSynced.addingTimeInterval(500)
        let fileC = settings(layoutsA, own: mineLayout, other: newC)
        let stateA = Policy.State(
            base: Policy.userDigest(of: mineA),
            baseLayoutDigest: Policy.layoutDigest(of: mineA, layouts: layoutsA),
            lastSynced: writtenA,
            versionDigest: Policy.userDigest(of: mineA),
            lastWritten: writtenA
        )
        let versionC = Policy.Version(settings: fileC, layouts: layoutsA, isFromThisMac: false, modified: concurrentC, isNewer: false)
        let idleA = Policy.Local(settings: mineA, layouts: layoutsA, state: stateA, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: idleA, file: .version(versionC)) == .ask)
        var keepsA = idleA
        keepsA.forcesWrite = true
        keepsA.keepsOver = versionC
        #expect(Policy.decide(.localChange, local: keepsA, file: .version(versionC)) == .write)
        let keptA = Policy.planWrite(mineA, file: fileC, fileCurrentLayouts: [layoutsA.own, layoutsA.other], fileCopiedLayouts: [], fileVersion: versionC, layouts: layoutsA, local: keepsA)
        #expect(keptA.copiedLayouts.contains(layoutsA.other))
        #expect(passOn(keptA, copy: newC, c: stateC(written: concurrentC)) == .apply)

        // (b) The sync app brings back C's older version with `midC` after A synced `newC`: A's
        // change passes `midC` on as a copy.
        let syncedC = lastSynced.addingTimeInterval(200)
        let syncedA = settings(layoutsA, own: mineLayout, other: newC)
        let stateB = Policy.State(
            base: Policy.userDigest(of: syncedA),
            baseLayoutDigest: Policy.layoutDigest(of: syncedA, layouts: layoutsA),
            lastSynced: syncedC,
            versionDigest: Policy.userDigest(of: syncedA)
        )
        let olderC = Policy.Version(settings: settings(layoutsA, own: mineLayout, other: midC), layouts: layoutsA, isFromThisMac: false, modified: lastSynced.addingTimeInterval(100), isNewer: false)
        let toggledA = settings(layoutsA, showOnHover: false, own: mineLayout, other: newC)
        let changedA = Policy.Local(settings: toggledA, layouts: layoutsA, state: stateB, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: changedA, file: .version(olderC)) == .write)
        let overOlder = Policy.planWrite(
            toggledA,
            file: settings(layoutsA, own: mineLayout, other: midC),
            fileCurrentLayouts: [layoutsA.own, layoutsA.other],
            fileCopiedLayouts: [],
            fileVersion: olderC,
            layouts: layoutsA,
            local: changedA
        )
        #expect(overOlder.copiedLayouts.contains(layoutsA.other))
        #expect(passOn(overOlder, copy: midC, c: stateC(written: syncedC)) == .apply)

        // (b') The file went away before A read `newC`: A's change inserts its copy, `midC`.
        let behindA = Policy.Local(settings: mineA, layouts: layoutsA, state: stateB, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: behindA, file: .missing) == .write)
        let overMissing = Policy.planWrite(mineA, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layoutsA, local: behindA)
        #expect(overMissing.insertsCopy)
        _ = passOn(overMissing, copy: midC, c: stateC(written: syncedC))
    }

    @Test("A newer version from another Mac that changed nothing this Mac uses is recorded as synced at launch", arguments: layoutBackends)
    func unchangedNewerVersionRecordedAtLaunch(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let syncedSettings = settings(layouts, own: first, other: second)
        let state = Policy.State(
            base: Policy.userDigest(of: syncedSettings),
            baseLayoutDigest: Policy.layoutDigest(of: syncedSettings, layouts: layouts),
            lastSynced: lastSynced,
            versionDigest: Policy.userDigest(of: syncedSettings)
        )
        let changed = Policy.Local(
            settings: settings(layouts, showOnHover: false, own: first, other: second),
            layouts: layouts,
            state: state,
            layoutEdits: 0,
            postponed: nil,
            forcesWrite: false
        )
        let newer = newerVersion(settings(layouts, own: first, other: third), layouts)
        #expect(Policy.decide(.launch, local: changed, file: .version(newer)) == .none)
        var launched = state
        launched.recordLaunch(.none, version: newer, local: changed, appliedBase: nil)
        #expect(launched.lastSynced == newer.modified)
        // Not for a version that is not newer, one of this Mac's, or one that changed something.
        for other in [
            newerVersion(settings(layouts, own: first, other: third), layouts, isNewer: false),
            Policy.Version(settings: settings(layouts, own: first, other: third), layouts: layouts, isFromThisMac: true, modified: newer.modified, isNewer: false),
            newerVersion(settings(layouts, own: third, other: third), layouts),
        ] {
            var unchanged = state
            unchanged.recordLaunch(.none, version: other, local: changed, appliedBase: nil)
            #expect(unchanged.lastSynced == lastSynced)
        }
        var joining = state
        joining.leaveFolder(forgetsLastSync: false)
        let joiningLocal = Policy.Local(settings: syncedSettings, layouts: layouts, state: joining, layoutEdits: 0, postponed: nil, forcesWrite: false)
        joining.recordLaunch(.none, version: newer, local: joiningLocal, appliedBase: nil)
        #expect(joining.lastSynced == lastSynced)
        // A check that finds nothing to do records it too.
        let outcome = Policy.outcome(of: .none, isCheck: true, version: newer, local: changed, state: state)
        #expect(outcome.state.lastSynced == newer.modified)
    }

    @Test("A write over a missing or unusable file never lists holzBar's own layout as current while this Mac keeps another Mac's layout", arguments: layoutBackends)
    func keptLayoutNotReplacedOverMissingFile(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // A kept B's arrangement (Keep This Mac's Settings without a layout change); the file
        // then went away, and A changes a setting.
        let mineLayout: [String: Any] = ["a": 0, "b": 1, "placed": 1]
        let keptLayout: [String: Any] = ["a": 5, "b": 1]
        let mine = settings(layouts, showOnHover: false, own: mineLayout)
        let state = Policy.State(
            base: Policy.userDigest(of: settings(layouts, own: mineLayout)),
            baseLayoutDigest: Policy.layoutDigest(of: mine, layouts: layouts),
            lastSynced: lastSynced,
            keptLayoutDigest: Policy.layoutDigest(of: settings(layouts, own: keptLayout), layouts: layouts)
        )
        let keeping = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.localChange, local: keeping, file: .missing) == .write)
        #expect(Policy.writesOwnLayoutAsCopy(fileSettings: nil, layouts: layouts, local: keeping))
        let plan = Policy.planWrite(mine, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: keeping)
        #expect(!plan.currentLayouts.contains(layouts.own))
        #expect(plan.copiedLayouts.contains(layouts.own))
        #expect(isLayout(plan.settings[layouts.own], mineLayout))
        #expect(!plan.record.takesInLayout)
        #expect(plan.record.keepsLayoutToTakeIn)
        // A keeps the record of B's arrangement, but nothing waits in the file any more.
        let firstWrite = lastSynced.addingTimeInterval(100)
        let afterFirst = Policy.outcome(of: .write, isCheck: false, version: nil, local: keeping, state: state, written: (plan.record, firstWrite))
        #expect(afterFirst.hint == .withdraw)
        #expect(afterFirst.state.keptLayoutDigest == state.keptLayoutDigest)
        #expect(afterFirst.state.baseLayoutDigest == Policy.noLayoutDigest)

        // A changes another setting before B writes: the write over A's own version passes
        // the copy on as a copy, and still keeps the record.
        let mineAgain = settings(layouts, showOnHover: true, own: mineLayout).merging(["ShowOnClick": false]) { $1 }
        let again = Policy.Local(settings: mineAgain, layouts: layouts, state: afterFirst.state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let ownVersion = Policy.Version(
            settings: Policy.withoutStaleLayouts(plan.settings, currentLayouts: Set(plan.currentLayouts)),
            layouts: layouts,
            isFromThisMac: true,
            modified: firstWrite,
            isNewer: false
        )
        #expect(Policy.decide(.localChange, local: again, file: .version(ownVersion)) == .write)
        let second = Policy.planWrite(
            mineAgain,
            file: plan.settings,
            fileCurrentLayouts: Set(plan.currentLayouts),
            fileCopiedLayouts: Set(plan.copiedLayouts),
            fileVersion: ownVersion,
            layouts: layouts,
            local: again
        )
        #expect(!second.currentLayouts.contains(layouts.own))
        #expect(second.copiedLayouts.contains(layouts.own))
        #expect(isLayout(second.settings[layouts.own], mineLayout))
        #expect(second.record.keepsLayoutToTakeIn)
        var afterSecond = afterFirst.state
        afterSecond.recordWrite(second.record, modified: firstWrite.addingTimeInterval(100), local: again)
        #expect(afterSecond.keptLayoutDigest == state.keptLayoutDigest)

        // A sync app brings back A's version from before, which holds B's arrangement: it is
        // taken in, not written over as an old copy of A's.
        let keptVersion = Policy.Version(
            settings: settings(layouts, own: keptLayout),
            layouts: layouts,
            isFromThisMac: true,
            modified: lastSynced.addingTimeInterval(-60),
            isNewer: false
        )
        let restored = Policy.Local(settings: mineAgain, layouts: layouts, state: afterSecond, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(!Policy.isOldOwnLayout(keptVersion, local: restored))
        #expect(Policy.decide(.launch, local: restored, file: .version(keptVersion)) == .takeInLayout)

        // B, which made that arrangement, applies A's changes and keeps it, at launch and
        // after either write.
        let mineB = settings(layouts, own: keptLayout)
        let localB = local(mineB, layouts, base: mineB)
        for written in [plan, second] {
            let readByB = Policy.withoutStaleLayouts(written.settings, currentLayouts: Set(written.currentLayouts))
            let versionForB = newerVersion(readByB, layouts)
            let action = Policy.decide(.launch, local: localB, file: .version(versionForB))
            #expect(action == .apply)
            let applied = Policy.settingsToApplyAtLaunch(for: action, remote: readByB, over: mineB, layouts: layouts, local: localB, version: versionForB)
            #expect(applied[layouts.own] == nil)
            #expect(applied["ShowOnHover"] as? Bool == (written.settings["ShowOnHover"] as? Bool))
        }
        // B's next write without a layout change passes the copy on as a copy; a layout change
        // of B's user lists B's arrangement as current again.
        let rewritten = Policy.planWrite(mineB, file: second.settings, fileCurrentLayouts: Set(second.currentLayouts), fileCopiedLayouts: Set(second.copiedLayouts), fileVersion: nil, layouts: layouts, local: localB)
        #expect(!rewritten.currentLayouts.contains(layouts.own))
        #expect(rewritten.copiedLayouts.contains(layouts.own))
        #expect(isLayout(rewritten.settings[layouts.own], mineLayout))
        #expect(!rewritten.record.keepsLayoutToTakeIn)
        var arranging = localB
        arranging.editsLayout = true
        let arranged = Policy.planWrite(mineB, file: second.settings, fileCurrentLayouts: Set(second.currentLayouts), fileCopiedLayouts: Set(second.copiedLayouts), fileVersion: nil, layouts: layouts, local: arranging)
        #expect(arranged.currentLayouts.contains(layouts.own))
        #expect(!arranged.copiedLayouts.contains(layouts.own))
        #expect(isLayout(arranged.settings[layouts.own], keptLayout))
        // Without a kept layout, or once A lists a layout as current, the record goes.
        var notKeepingLayout = again
        notKeepingLayout.keptLayoutDigest = nil
        #expect(!Policy.planWrite(mineAgain, file: plan.settings, fileCurrentLayouts: Set(plan.currentLayouts), fileCopiedLayouts: Set(plan.copiedLayouts), fileVersion: ownVersion, layouts: layouts, local: notKeepingLayout).record.keepsLayoutToTakeIn)
        var editedAgain = again
        editedAgain.editsLayout = true
        let listed = Policy.planWrite(mineAgain, file: plan.settings, fileCurrentLayouts: Set(plan.currentLayouts), fileCopiedLayouts: Set(plan.copiedLayouts), fileVersion: ownVersion, layouts: layouts, local: editedAgain)
        #expect(listed.currentLayouts.contains(layouts.own))
        #expect(!listed.record.keepsLayoutToTakeIn)
        var afterListed = afterFirst.state
        afterListed.recordWrite(listed.record, modified: firstWrite.addingTimeInterval(100), local: editedAgain)
        #expect(afterListed.keptLayoutDigest == nil)

        // A layout change of the user's is written as current, as is a write without a kept
        // layout or over a file that is there.
        var edited = keeping
        edited.editsLayout = true
        #expect(Policy.planWrite(mine, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: edited).currentLayouts.contains(layouts.own))
        var notKeeping = keeping
        notKeeping.keptLayoutDigest = nil
        #expect(Policy.planWrite(mine, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: notKeeping).currentLayouts.contains(layouts.own))
        // A file that holds no layout for this macOS version, as one a Mac of the other
        // macOS version wrote, is written the same way; one that holds it is not.
        #expect(Policy.writesOwnLayoutAsCopy(fileSettings: settings(layouts, other: ["o": 1]), layouts: layouts, local: keeping))
        let overNoLayout = Policy.planWrite(mine, file: settings(layouts, other: ["o": 1]), fileCurrentLayouts: [layouts.other], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: keeping)
        #expect(!overNoLayout.currentLayouts.contains(layouts.own))
        #expect(overNoLayout.copiedLayouts.contains(layouts.own))
        #expect(overNoLayout.record.keepsLayoutToTakeIn)
        #expect(!Policy.writesOwnLayoutAsCopy(fileSettings: settings(layouts, own: keptLayout), layouts: layouts, local: keeping))
        // A write without a layout change of the user's that lists a layout as current, here
        // the one this Mac last synced, ends the record.
        let syncedLayout = settings(layouts, own: mineLayout)
        let overSynced = Policy.planWrite(mine, file: syncedLayout, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: keeping)
        #expect(overSynced.currentLayouts.contains(layouts.own))
        #expect(!overSynced.record.takesInLayout)
        #expect(!overSynced.record.keepsLayoutToTakeIn)
        var afterSynced = state
        afterSynced.recordWrite(overSynced.record, modified: lastSynced.addingTimeInterval(100), local: keeping)
        #expect(afterSynced.keptLayoutDigest == nil)
    }

    // MARK: The writes a version holds

    /// The version a Mac reads from the file another Mac wrote with `plan`, through the file's
    /// contents as read, and its current settings.
    private func read(
        _ plan: Policy.WritePlan,
        writer: String,
        modified: Date,
        reader: String,
        layouts: Policy.Layouts,
        lastSynced: Date?
    ) throws -> (version: Policy.Version, settings: [String: Any]) {
        let file = SettingsSyncFile.fileToWrite(plan: plan, deviceID: writer, modified: modified)
        let contents = try #require(
            SettingsSyncFile.contents(of: file, lastSynced: lastSynced, deviceID: reader, computerName: nil, localKeys: [], now: modified)
        )
        let current = Policy.withoutStaleLayouts(contents.settings, currentLayouts: contents.currentLayouts)
        let version = Policy.Version(
            settings: current,
            layouts: layouts,
            isFromThisMac: contents.isFromThisMac,
            modified: contents.modified,
            isNewer: contents.isNewer,
            unlistedLayoutDigest: Policy.unlistedLayoutDigest(
                in: contents.settings,
                currentLayouts: contents.currentLayouts,
                copiedLayouts: contents.copiedLayouts,
                layouts: layouts
            ),
            seen: contents.seen,
            seenWrite: contents.seenWrite
        )
        return (version, current)
    }

    @Test("A version written without this Mac's last write asks instead of reverting it, as after a write over a missing file, however many writes follow", arguments: layoutBackends)
    func versionWithoutLastWriteAsks(backend: MenuBarBackendKind) throws {
        let layouts = Policy.Layouts(backend: backend)
        // A and B synced V1, which B wrote. B changed a setting and wrote V2.
        let v1Settings = settings(layouts, own: first)
        let v2Settings = settings(layouts, showOnHover: false, own: first)
        let v2Modified = lastSynced.addingTimeInterval(120.6)
        let synced = Policy.State(
            base: Policy.userDigest(of: v1Settings),
            baseLayoutDigest: Policy.layoutDigest(of: v1Settings, layouts: layouts),
            lastSynced: lastSynced,
            versionDigest: Policy.userDigest(of: v1Settings)
        )
        var stateA = synced
        stateA.seen = ["B": lastSynced]
        var stateB = synced
        stateB.lastWritten = lastSynced
        let localB = Policy.Local(settings: v2Settings, layouts: layouts, state: stateB, layoutEdits: 0, postponed: nil, forcesWrite: false)
        stateB.recordWrite(Policy.WriteRecord(layoutDigest: localB.layoutDigest, takesInLayout: false), modified: v2Modified, local: localB)
        #expect(stateB.lastWritten == v2Modified)
        let idleB = Policy.Local(settings: v2Settings, layouts: layouts, state: stateB, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(!idleB.hasChanges)

        // The file went away before A read V2; A writes its own change over the missing file.
        // It holds only the writes A's settings hold.
        let changedA = settings(layouts, own: second)
        var localA = Policy.Local(settings: changedA, layouts: layouts, state: stateA, layoutEdits: 1, postponed: nil, forcesWrite: false)
        localA.editsLayout = true
        #expect(Policy.decide(.localChange, local: localA, file: .missing) == .write)
        let plan = Policy.planWrite(changedA, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: localA)
        #expect(plan.seen == ["B": lastSynced])
        let v3Modified = lastSynced.addingTimeInterval(300)

        // B changed nothing since, but A's version lacks B's change: B asks, at launch and
        // while it runs, instead of reverting it.
        let v3 = try read(plan, writer: "A", modified: v3Modified, reader: "B", layouts: layouts, lastSynced: stateB.lastSynced).version
        #expect(v3.seenWrite == lastSynced)
        #expect(Policy.missesLastWrite(v3, local: idleB))
        #expect(Policy.decide(.launch, local: idleB, file: .version(v3)) == .ask)
        #expect(Policy.decide(.check, local: idleB, file: .version(v3)) == .ask)
        #expect(Policy.hint(for: idleB, version: v3) == .choice(isJoining: false))

        // A writes again, over its own version, before B reads it: still without B's change.
        stateA = Policy.outcome(of: .write, isCheck: false, version: nil, local: localA, state: stateA, written: (plan.record, v3Modified)).state
        #expect(stateA.lastSynced == v3Modified)
        let againA = settings(layouts, own: second).merging(["ShowOnClick": false]) { $1 }
        let localA2 = Policy.Local(settings: againA, layouts: layouts, state: stateA, layoutEdits: 1, postponed: nil, forcesWrite: false)
        let ownV3 = try read(plan, writer: "A", modified: v3Modified, reader: "A", layouts: layouts, lastSynced: stateA.lastSynced).version
        #expect(ownV3.isFromThisMac)
        #expect(Policy.decide(.localChange, local: localA2, file: .version(ownV3)) == .write)
        let plan2 = Policy.planWrite(againA, file: plan.settings, fileCurrentLayouts: Set(plan.currentLayouts), fileCopiedLayouts: Set(plan.copiedLayouts), fileVersion: ownV3, layouts: layouts, local: localA2)
        #expect(plan2.seen == ["B": lastSynced])
        let v4 = try read(plan2, writer: "A", modified: v3Modified.addingTimeInterval(100), reader: "B", layouts: layouts, lastSynced: stateB.lastSynced).version
        #expect(Policy.missesLastWrite(v4, local: idleB))
        #expect(Policy.decide(.launch, local: idleB, file: .version(v4)) == .ask)

        // A third Mac applies A's version and writes on top of it: still without B's change.
        let readByC = try read(plan, writer: "A", modified: v3Modified, reader: "C", layouts: layouts, lastSynced: lastSynced)
        var stateC = synced
        stateC.recordApplied(readByC.version, base: Policy.userDigest(of: readByC.settings), layoutDigest: readByC.version.layoutDigest)
        #expect(stateC.seen == ["A": v3Modified, "B": lastSynced])
        let changedC = readByC.settings.merging(["ShowOnScroll": false]) { $1 }
        let localC = Policy.Local(settings: changedC, layouts: layouts, state: stateC, layoutEdits: 0, postponed: nil, forcesWrite: false)
        var overV3 = readByC.version
        overV3.isNewer = false
        #expect(Policy.decide(.localChange, local: localC, file: .version(overV3)) == .write)
        let planC = Policy.planWrite(changedC, file: plan.settings, fileCurrentLayouts: Set(plan.currentLayouts), fileCopiedLayouts: Set(plan.copiedLayouts), fileVersion: overV3, layouts: layouts, local: localC)
        let v5 = try read(planC, writer: "C", modified: v3Modified.addingTimeInterval(200), reader: "B", layouts: layouts, lastSynced: stateB.lastSynced).version
        #expect(v5.seen?["A"] == v3Modified)
        #expect(Policy.missesLastWrite(v5, local: idleB))
        #expect(Policy.decide(.launch, local: idleB, file: .version(v5)) == .ask)

        // A version that holds V2, in whole seconds as the file stores it, is applied as usual.
        var holdsV2 = v3
        holdsV2.seenWrite = Date(timeIntervalSinceReferenceDate: Policy.wholeSeconds(v2Modified))
        #expect(!Policy.missesLastWrite(holdsV2, local: idleB))
        #expect(Policy.decide(.check, local: idleB, file: .version(holdsV2)) == .apply)
        #expect(Policy.hint(for: idleB, version: holdsV2) == .restart)
        // A file of an earlier build records no writes, and is decided as before.
        var earlier = v3
        earlier.seen = nil
        earlier.seenWrite = nil
        #expect(Policy.decide(.check, local: idleB, file: .version(earlier)) == .apply)
        // Without a write of its own, a Mac has nothing to lose; a joining Mac asks anyway when
        // the settings differ; and this Mac's own version is no other Mac's.
        var neverWrote = idleB
        neverWrote.lastWritten = nil
        #expect(!Policy.missesLastWrite(v3, local: neverWrote))
        var joining = idleB
        joining.base = nil
        #expect(!Policy.missesLastWrite(v3, local: joining))
        var own = v3
        own.isFromThisMac = true
        #expect(!Policy.missesLastWrite(own, local: idleB))

        // The user chooses A's version on B: B's settings hold what it holds, and the versions
        // written on top of it no longer ask.
        var usedB = stateB
        usedB.recordUse(of: v3, layoutDigest: v3.layoutDigest, base: Policy.userDigest(of: changedA))
        #expect(usedB.lastWritten == v3.seenWrite)
        #expect(usedB.seen == ["A": v3Modified])
        let afterUse = Policy.Local(settings: changedA, layouts: layouts, state: usedB, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(!Policy.missesLastWrite(v4, local: afterUse))
        #expect(!Policy.missesLastWrite(v5, local: afterUse))
        // Applying a version of an earlier build leaves no write to look for.
        var appliedEarlier = stateB
        appliedEarlier.recordApplied(earlier, base: Policy.userDigest(of: changedA), layoutDigest: nil)
        #expect(appliedEarlier.lastWritten == nil)
        #expect(appliedEarlier.seen.isEmpty)
    }

    @Test("A Mac asks about a version without another Mac's write that its settings hold, as a third Mac after a write over a missing file", arguments: layoutBackends)
    func versionWithoutHeldWriteOfAnotherMacAsks(backend: MenuBarBackendKind) throws {
        let layouts = Policy.Layouts(backend: backend)
        // A, B and C synced C's version, written at `writtenC`. A rearranged to `second` and
        // wrote it at `writtenA`; C applied A's version, B never read it.
        let synced = settings(layouts, own: first)
        let writtenC = lastSynced
        let writtenA = lastSynced.addingTimeInterval(100.4)
        let both = Policy.State(
            base: Policy.userDigest(of: synced),
            baseLayoutDigest: Policy.layoutDigest(of: synced, layouts: layouts),
            lastSynced: lastSynced,
            versionDigest: Policy.userDigest(of: synced)
        )
        var stateA = both
        stateA.seen = ["C": writtenC]
        let mineA = settings(layouts, own: second)
        var editA = Policy.Local(settings: mineA, layouts: layouts, state: stateA, layoutEdits: 1, postponed: nil, forcesWrite: false)
        editA.editsLayout = true
        let planA = Policy.planWrite(mineA, file: synced, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: editA)
        let readByC = try read(planA, writer: "A", modified: writtenA, reader: "C", layouts: layouts, lastSynced: lastSynced)
        var stateC = both
        stateC.lastWritten = writtenC
        stateC.recordApplied(readByC.version, base: Policy.userDigest(of: readByC.settings), layoutDigest: readByC.version.layoutDigest)
        #expect(stateC.lastWritten == writtenC)
        #expect(stateC.seen["A"] == writtenA)
        let idleC = Policy.Local(settings: mineA, layouts: layouts, state: stateC, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(!idleC.hasChanges)

        // The file went away; B changed a setting and wrote over the missing file. B's version
        // holds C's write but not A's.
        var stateB = both
        stateB.seen = ["A": lastSynced, "C": writtenC]
        let mineB = settings(layouts, showOnHover: false, own: first)
        let changedB = Policy.Local(settings: mineB, layouts: layouts, state: stateB, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let planB = Policy.planWrite(mineB, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: changedB)
        let versionB = try read(planB, writer: "B", modified: lastSynced.addingTimeInterval(200), reader: "C", layouts: layouts, lastSynced: stateC.lastSynced).version
        #expect(versionB.isNewer)
        #expect(versionB.seenWrite == writtenC)

        // C's own write is in it, A's is not: C asks, at launch and while it runs, instead of
        // reverting A's arrangement.
        #expect(Policy.missesLastWrite(versionB, local: idleC))
        #expect(Policy.decide(.launch, local: idleC, file: .version(versionB)) == .ask)
        #expect(Policy.decide(.check, local: idleC, file: .version(versionB)) == .ask)
        #expect(Policy.hint(for: idleC, version: versionB) == .choice(isJoining: false))

        // A version that holds A's write, in whole seconds as the file stores it, is applied;
        // so is one from a Mac whose writes C holds none of.
        var holdsA = versionB
        holdsA.seen?["A"] = Date(timeIntervalSinceReferenceDate: Policy.wholeSeconds(writtenA))
        #expect(!Policy.missesLastWrite(holdsA, local: idleC))
        #expect(Policy.decide(.check, local: idleC, file: .version(holdsA)) == .apply)
        var heldNone = idleC
        heldNone.seen = [:]
        #expect(!Policy.missesLastWrite(versionB, local: heldNone))
        // A version that records no writes, as an earlier build's, is decided as before.
        var earlier = versionB
        earlier.seen = nil
        earlier.seenWrite = nil
        #expect(!Policy.missesLastWrite(earlier, local: idleC))
    }

    @Test("A version written on top of a version this Mac asks about, without this Mac's last write, still asks", arguments: layoutBackends)
    func descendantOfAskedVersionAsks(backend: MenuBarBackendKind) throws {
        let layouts = Policy.Layouts(backend: backend)
        // C wrote `second`; B wrote concurrently from the version before, which C wrote too,
        // and the sync app kept B's.
        let writtenC = lastSynced.addingTimeInterval(100)
        let mineC = settings(layouts, own: second)
        let stateC = Policy.State(
            base: Policy.userDigest(of: mineC),
            baseLayoutDigest: Policy.layoutDigest(of: mineC, layouts: layouts),
            lastSynced: writtenC,
            versionDigest: Policy.userDigest(of: mineC),
            lastWritten: writtenC
        )
        let idleC = Policy.Local(settings: mineC, layouts: layouts, state: stateC, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let synced = Policy.State(base: Policy.userDigest(of: mineC), baseLayoutDigest: nil, lastSynced: lastSynced, seen: ["C": lastSynced])
        let fileB = settings(layouts, own: first)
        let localB = Policy.Local(settings: fileB, layouts: layouts, state: synced, layoutEdits: 1, postponed: nil, forcesWrite: false)
        let planB = Policy.planWrite(fileB, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: localB)
        let writtenB = lastSynced.addingTimeInterval(110)
        let versionB = try read(planB, writer: "B", modified: writtenB, reader: "C", layouts: layouts, lastSynced: writtenC).version
        #expect(Policy.decide(.check, local: idleC, file: .version(versionB)) == .ask)
        let asked = Policy.outcome(of: .ask, isCheck: true, version: versionB, local: idleC, state: stateC)
        #expect(asked.state.pending == versionB.modified)
        let waitingC = Policy.Local(settings: mineC, layouts: layouts, state: asked.state, layoutEdits: 0, postponed: nil, forcesWrite: false)

        // D applies B's version and writes a change on top of it.
        let readByD = try read(planB, writer: "B", modified: writtenB, reader: "D", layouts: layouts, lastSynced: lastSynced)
        var stateD = synced
        stateD.recordApplied(readByD.version, base: Policy.userDigest(of: readByD.settings), layoutDigest: readByD.version.layoutDigest)
        let changedD = readByD.settings.merging(["ShowOnClick": false]) { $1 }
        let localD = Policy.Local(settings: changedD, layouts: layouts, state: stateD, layoutEdits: 0, postponed: nil, forcesWrite: false)
        var overB = readByD.version
        overB.isNewer = false
        let planD = Policy.planWrite(changedD, file: planB.settings, fileCurrentLayouts: Set(planB.currentLayouts), fileCopiedLayouts: Set(planB.copiedLayouts), fileVersion: overB, layouts: layouts, local: localD)
        let versionD = try read(planD, writer: "D", modified: lastSynced.addingTimeInterval(200), reader: "C", layouts: layouts, lastSynced: writtenC).version

        // C still asks, and its hint still asks; the launch never applies it silently.
        #expect(Policy.missesLastWrite(versionD, local: waitingC))
        #expect(Policy.decide(.check, local: waitingC, file: .version(versionD)) == .ask)
        #expect(Policy.hint(for: waitingC, version: versionD) == .choice(isJoining: false))
        #expect(Policy.decide(.launch, local: waitingC, file: .version(versionD)) == .ask)
    }

    @Test("A write passes on the writes the written settings hold, and each sync records them", arguments: layoutBackends)
    func seenRecorded(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, showOnHover: false, own: first)
        let earlierWrite = lastSynced.addingTimeInterval(-100)
        var state = Policy.State(base: Policy.userDigest(of: settings(layouts, own: first)), baseLayoutDigest: nil, lastSynced: lastSynced, seen: ["B": earlierWrite, "C": lastSynced])
        let changed = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(changed.seen == state.seen)
        var newer = newerVersion(settings(layouts, own: first), layouts)
        newer.seen = ["B": lastSynced, "C": earlierWrite, "D": earlierWrite]
        // The newest write of each Mac, from this Mac's settings and the version written over;
        // over a missing file, or a file of an earlier build, only this Mac's.
        #expect(Policy.seen(writingOver: newer, local: changed) == ["B": lastSynced, "C": lastSynced, "D": earlierWrite])
        #expect(Policy.seen(writingOver: nil, local: changed) == state.seen)
        var earlier = newer
        earlier.seen = nil
        #expect(Policy.seen(writingOver: earlier, local: changed) == state.seen)
        let plan = Policy.planWrite(mine, file: settings(layouts, own: first), fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: newer, layouts: layouts, local: changed)
        #expect(plan.seen == ["B": lastSynced, "C": lastSynced, "D": earlierWrite])
        #expect(plan.record.seen == plan.seen)
        var written = state
        written.recordWrite(plan.record, modified: lastSynced.addingTimeInterval(60), local: changed)
        #expect(written.seen == plan.seen)
        #expect(written.lastWritten == lastSynced.addingTimeInterval(60))

        // An adoption holds the version's writes, unless its layout waits for a restart.
        var adopted = state
        adopted.recordAdoption(newer, local: changed, takesInOwnLayout: false)
        #expect(adopted.seen == plan.seen)
        var waiting = state
        waiting.recordAdoption(newer, local: changed, takesInOwnLayout: true)
        #expect(waiting.seen == state.seen)
        var ownWaiting = state
        var own = newer
        own.isFromThisMac = true
        ownWaiting.recordAdoption(own, local: changed, takesInOwnLayout: true)
        #expect(ownWaiting.seen == plan.seen)
        // Applying a version replaces them with the version's; a version of an earlier build
        // holds none.
        var applied = state
        applied.recordApplied(newer, base: "base", layoutDigest: nil)
        #expect(applied.seen == newer.seen)
        // Leaving the folder for one this Mac has not synced with forgets them.
        state.lastWritten = lastSynced
        var left = state
        left.leaveFolder(forgetsLastSync: false)
        #expect(left.lastWritten == lastSynced)
        #expect(left.seen == state.seen)
        left.leaveFolder(forgetsLastSync: true)
        #expect(left.lastWritten == nil)
        #expect(left.seen.isEmpty)
        // Too many writes keep the newest.
        var many = [String: Date]()
        for index in 0 ..< 70 {
            many["mac\(index)"] = lastSynced.addingTimeInterval(Double(index))
        }
        #expect(Policy.mergedSeen(many, ["new": lastSynced.addingTimeInterval(100)]).count == SettingsSyncFile.seenLimit)
        #expect(Policy.mergedSeen(many, ["new": lastSynced.addingTimeInterval(100)])["new"] != nil)
    }

    @Test("A joining Mac asks about another Mac's version that is not newer and holds a layout it never synced", arguments: layoutBackends)
    func joiningAsksAboutOlderLayout(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        // This Mac synced `first`, holzBar placed an item since, and sync was turned off and on.
        let syncedSettings = settings(layouts, own: first)
        let mine = settings(layouts, own: first.merging(["placed": 1]) { $1 })
        var state = Policy.State(
            base: Policy.userDigest(of: syncedSettings),
            baseLayoutDigest: Policy.layoutDigest(of: syncedSettings, layouts: layouts),
            lastSynced: lastSynced,
            versionDigest: Policy.userDigest(of: syncedSettings)
        )
        state.leaveFolder(forgetsLastSync: false)
        let joining = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: false)
        // Another Mac's version dated before the last sync, with the same user settings and
        // another arrangement.
        let theirs = newerVersion(settings(layouts, own: third), layouts, isNewer: false)
        #expect(Policy.holdsOlderLayoutToJoin(theirs, local: joining))
        #expect(Policy.decide(.check, local: joining, file: .version(theirs)) == .ask)
        #expect(Policy.decide(.launch, local: joining, file: .version(theirs)) == .ask)
        #expect(Policy.hint(for: joining, version: theirs) == .choice(isJoining: true))
        var postponed = joining
        postponed.postponed = theirs.modified
        #expect(Policy.decide(.check, local: postponed, file: .version(theirs)) == .wait)

        // "Keep This Mac's Settings" for that question writes this Mac's layout, as the
        // version's may be stale; never at launch. Over a version that was not asked about it
        // still asks.
        var keeps = joining
        keeps.forcesWrite = true
        keeps.keepsOver = theirs
        #expect(Policy.decide(.localChange, local: keeps, file: .version(theirs)) == .write)
        #expect(Policy.decide(.launch, local: keeps, file: .version(theirs)) == .none)
        let kept = Policy.planWrite(
            mine,
            file: settings(layouts, own: third),
            fileCurrentLayouts: [layouts.own],
            fileCopiedLayouts: [],
            fileVersion: theirs,
            layouts: layouts,
            local: keeps
        )
        // This Mac's arrangement, listed as current; nothing to take in.
        #expect(isLayout(kept.settings[layouts.own], first.merging(["placed": 1]) { $1 }))
        #expect(kept.currentLayouts.contains(layouts.own))
        #expect(!kept.record.takesInLayout)
        var unasked = theirs
        unasked.modified = theirs.modified.addingTimeInterval(-30)
        #expect(Policy.decide(.localChange, local: keeps, file: .version(unasked)) == .ask)
        var notKept = keeps
        notKept.forcesWrite = false
        #expect(Policy.decide(.localChange, local: notKept, file: .version(theirs)) == .ask)

        // The layout this Mac last synced, or holds, is adopted as before; so is a newer
        // version, whose layout is taken in.
        let synced = newerVersion(syncedSettings, layouts, isNewer: false)
        #expect(Policy.decide(.check, local: joining, file: .version(synced)) == .adopt)
        let held = newerVersion(mine, layouts, isNewer: false)
        #expect(Policy.decide(.check, local: joining, file: .version(held)) == .adopt)
        let newer = newerVersion(settings(layouts, own: third), layouts)
        #expect(!Policy.holdsOlderLayoutToJoin(newer, local: joining))
        #expect(Policy.decide(.check, local: joining, file: .version(newer)) == .adopt)
        // Not for a Mac that is not joining, which asks through isUnsyncedChange, for a layout
        // change of the user's, this Mac's own version, or a version without a layout.
        let notJoining = Policy.Local(
            settings: mine,
            layouts: layouts,
            state: Policy.State(base: state.baseLayoutDigest.map { _ in Policy.userDigest(of: syncedSettings) }, baseLayoutDigest: state.baseLayoutDigest, lastSynced: lastSynced),
            layoutEdits: 0,
            postponed: nil,
            forcesWrite: false
        )
        #expect(!Policy.holdsOlderLayoutToJoin(theirs, local: notJoining))
        var edited = joining
        edited.editsLayout = true
        #expect(!Policy.holdsOlderLayoutToJoin(theirs, local: edited))
        var own = theirs
        own.isFromThisMac = true
        #expect(!Policy.holdsOlderLayoutToJoin(own, local: joining))
        var noLayout = theirs
        noLayout.layoutDigest = nil
        #expect(!Policy.holdsOlderLayoutToJoin(noLayout, local: joining))
        var neverSynced = joining
        neverSynced.baseLayoutDigest = nil
        #expect(!Policy.holdsOlderLayoutToJoin(theirs, local: neverSynced))
    }

    @Test("Keep This Mac's Settings over another Mac's version not newer than the last sync writes this Mac's layout, so no Mac takes the stale one back", arguments: layoutBackends, [false, true])
    func keepOverOlderVersionWritesOwnLayout(backend: MenuBarBackendKind, joining: Bool) throws {
        let layouts = Policy.Layouts(backend: backend)
        // A and C synced C's newest arrangement `second` at `synced`. A sync app brings back
        // B's version from before, with the older arrangement `first`.
        let mine = settings(layouts, own: second)
        let synced = lastSynced.addingTimeInterval(200)
        let syncedState = Policy.State(
            base: Policy.userDigest(of: mine),
            baseLayoutDigest: Policy.layoutDigest(of: mine, layouts: layouts),
            lastSynced: synced,
            versionDigest: Policy.userDigest(of: mine),
            lastWritten: nil,
            seen: ["C": synced]
        )
        var stateA = syncedState
        if joining {
            stateA.leaveFolder(forgetsLastSync: false)
        }
        let older = settings(layouts, own: first)
        let restored = Policy.Version(settings: older, layouts: layouts, isFromThisMac: false, modified: lastSynced.addingTimeInterval(100), isNewer: false)
        let idleA = Policy.Local(settings: mine, layouts: layouts, state: stateA, layoutEdits: 0, postponed: nil, forcesWrite: false)
        #expect(Policy.decide(.check, local: idleA, file: .version(restored)) == .ask)

        // The user answers "Keep This Mac's Settings": A writes its own arrangement as current,
        // and has nothing to take in at its restart.
        var keepA = idleA
        keepA.forcesWrite = true
        keepA.keepsOver = restored
        #expect(Policy.decide(.localChange, local: keepA, file: .version(restored)) == .write)
        #expect(Policy.keepsOwnLayoutOverStale(restored, local: keepA))
        let plan = Policy.planWrite(mine, file: older, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: restored, layouts: layouts, local: keepA)
        #expect(plan.currentLayouts.contains(layouts.own))
        #expect(isLayout(plan.settings[layouts.own], second))
        #expect(!plan.record.takesInLayout)
        let afterKeep = Policy.outcome(of: .write, isCheck: false, version: restored, local: keepA, state: stateA, written: (plan.record, synced.addingTimeInterval(100)))
        #expect(afterKeep.hint == .withdraw)
        #expect(afterKeep.state.keptLayoutDigest == nil)
        #expect(afterKeep.state.baseLayoutDigest == Policy.layoutDigest(of: mine, layouts: layouts))

        // C, which arranged `second`, keeps it: A's version holds its settings.
        var stateC = syncedState
        stateC.lastWritten = synced
        stateC.seen = [:]
        let idleC = Policy.Local(settings: mine, layouts: layouts, state: stateC, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let forC = try read(plan, writer: "A", modified: synced.addingTimeInterval(100), reader: "C", layouts: layouts, lastSynced: synced)
        #expect(forC.version.layoutDigest == Policy.layoutDigest(of: mine, layouts: layouts))
        #expect(Policy.decide(.launch, local: idleC, file: .version(forC.version)) == .adopt)

        // Only a stale layout is written over: a version that lists the layout this Mac last
        // synced keeps the file's, without holzBar's own placements since; so does a newer
        // version, whose layout this Mac then takes in, and a version the user did not answer.
        var placed = second
        placed["b"] = 2
        let placedMine = settings(layouts, own: placed)
        var keepSame = Policy.Local(settings: placedMine, layouts: layouts, state: stateA, layoutEdits: 0, postponed: nil, forcesWrite: true)
        let sameLayout = Policy.Version(settings: settings(layouts, showOnHover: false, own: second), layouts: layouts, isFromThisMac: false, modified: restored.modified, isNewer: false)
        keepSame.keepsOver = sameLayout
        #expect(!Policy.keepsOwnLayoutOverStale(sameLayout, local: keepSame))
        let samePlan = Policy.planWrite(placedMine, file: settings(layouts, showOnHover: false, own: second), fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: sameLayout, layouts: layouts, local: keepSame)
        #expect(isLayout(samePlan.settings[layouts.own], second))
        var newer = restored
        newer.isNewer = true
        var keepNewer = keepA
        keepNewer.keepsOver = newer
        #expect(!Policy.keepsOwnLayoutOverStale(newer, local: keepNewer))
        var notAnswered = keepA
        notAnswered.keepsOver = nil
        #expect(!Policy.keepsOwnLayoutOverStale(restored, local: notAnswered))
        #expect(!Policy.keepsOwnLayoutOverStale(restored, local: idleA))
        #expect(!Policy.keepsOwnLayoutOverStale(nil, local: keepA))
    }

    @Test("Keep This Mac's Settings answering a version without this Mac's last write keeps this Mac's arrangement", arguments: layoutBackends)
    func keepOverVersionWithoutLastWriteKeepsArrangement(backend: MenuBarBackendKind) throws {
        let layouts = Policy.Layouts(backend: backend)
        // A and B synced `first`. A rearranged to `second` and wrote it; the file went away
        // before B read it, and B wrote a change of a setting over the missing file, listing
        // its `first` as current.
        let synced = settings(layouts, own: first)
        let both = Policy.State(
            base: Policy.userDigest(of: synced),
            baseLayoutDigest: Policy.layoutDigest(of: synced, layouts: layouts),
            lastSynced: lastSynced,
            versionDigest: Policy.userDigest(of: synced),
            lastWritten: lastSynced
        )
        var stateA = both
        stateA.seen = ["B": lastSynced]
        var stateB = both
        stateB.seen = ["A": lastSynced]
        let mineA = settings(layouts, own: second)
        var editA = Policy.Local(settings: mineA, layouts: layouts, state: stateA, layoutEdits: 1, postponed: nil, forcesWrite: false)
        editA.editsLayout = true
        let planA = Policy.planWrite(mineA, file: synced, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: editA)
        let writtenA = lastSynced.addingTimeInterval(100)
        stateA = Policy.outcome(of: .write, isCheck: false, version: nil, local: editA, state: stateA, written: (planA.record, writtenA)).state
        stateA.layoutEdits = 1
        let mineB = settings(layouts, showOnHover: false, own: first)
        let changedB = Policy.Local(settings: mineB, layouts: layouts, state: stateB, layoutEdits: 0, postponed: nil, forcesWrite: false)
        let planB = Policy.planWrite(mineB, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], fileVersion: nil, layouts: layouts, local: changedB)
        let versionB = try read(planB, writer: "B", modified: lastSynced.addingTimeInterval(200), reader: "A", layouts: layouts, lastSynced: stateA.lastSynced)
        #expect(versionB.version.isNewer)
        #expect(versionB.version.layoutDigest == Policy.layoutDigest(of: synced, layouts: layouts))

        // A asks; "Keep This Mac's Settings" writes A's arrangement, and A takes nothing in.
        let idleA = Policy.Local(settings: mineA, layouts: layouts, state: stateA, layoutEdits: 1, postponed: nil, forcesWrite: false)
        #expect(!idleA.editsLayout)
        #expect(Policy.decide(.check, local: idleA, file: .version(versionB.version)) == .ask)
        var keepA = idleA
        keepA.forcesWrite = true
        keepA.keepsOver = versionB.version
        #expect(Policy.decide(.localChange, local: keepA, file: .version(versionB.version)) == .write)
        #expect(Policy.keepsOwnLayoutOverStale(versionB.version, local: keepA))
        let kept = Policy.planWrite(
            mineA,
            file: planB.settings,
            fileCurrentLayouts: Set(planB.currentLayouts),
            fileCopiedLayouts: Set(planB.copiedLayouts),
            fileVersion: versionB.version,
            layouts: layouts,
            local: keepA
        )
        #expect(kept.currentLayouts.contains(layouts.own))
        #expect(isLayout(kept.settings[layouts.own], second))
        #expect(!kept.record.takesInLayout)
        let afterKeep = Policy.outcome(of: .write, isCheck: false, version: versionB.version, local: keepA, state: stateA, written: (kept.record, lastSynced.addingTimeInterval(300)))
        #expect(afterKeep.hint == .withdraw)
        #expect(afterKeep.state.keptLayoutDigest == nil)

        // A version that holds A's last write keeps its layout, which A then takes in.
        var holdsWrite = versionB.version
        holdsWrite.seenWrite = writtenA
        var keepHolds = keepA
        keepHolds.keepsOver = holdsWrite
        #expect(!Policy.keepsOwnLayoutOverStale(holdsWrite, local: keepHolds))
    }

    // MARK: What the launch applies

    @Test("The launch applies for each decision exactly what the decision says", arguments: layoutBackends)
    func settingsToApplyAtLaunch(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let mine = settings(layouts, own: first, other: second)
        let remote = settings(layouts, showOnHover: false, own: third, other: third)
        let synced = local(mine, layouts, base: mine)
        let version = newerVersion(remote, layouts)
        func applied(_ action: Policy.Action, local: Policy.Local, version: Policy.Version) -> [String: Any] {
            Policy.settingsToApplyAtLaunch(for: action, remote: remote, over: mine, layouts: layouts, local: local, version: version)
        }
        // A version applied whole.
        let whole = applied(.apply, local: synced, version: version)
        #expect(whole["ShowOnHover"] as? Bool == false)
        // This Mac's items the version has never seen stay.
        let merged = third.merging(["b": 1]) { $1 }
        #expect(isLayout(whole[layouts.own], merged))
        // A joining Mac's adoption takes in only the folder's layout of its macOS version.
        var joining = synced
        joining.base = nil
        let adopted = applied(.adopt, local: joining, version: version)
        #expect(Set(adopted.keys) == [layouts.own])
        #expect(isLayout(adopted[layouts.own], merged))
        #expect(applied(.adopt, local: synced, version: version).isEmpty)
        // A kept layout of this Mac's own version.
        var own = version
        own.isFromThisMac = true
        let kept = applied(.takeInLayout, local: synced, version: own)
        #expect(Set(kept.keys) == [layouts.own])
        // Nothing else.
        for action in [Policy.Action.none, .ask, .write, .wait, .retry] {
            #expect(applied(action, local: synced, version: version).isEmpty)
        }
    }

    @Test("A Mac that synced takes in the learned settings at launch, and the other macOS version's layout only from a version not older than its last sync", arguments: layoutBackends)
    func settingsToTakeInAtLaunch(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let seeded = Defaults.Key.macOS27LayoutSeeded.rawValue
        let mine = settings(layouts, own: first, other: second)
        var remote = settings(layouts, own: first, other: third)
        remote[seeded] = true
        var synced = local(mine, layouts, base: mine)
        synced.lastSynced = lastSynced
        let newer = newerVersion(remote, layouts)
        let takenIn = Policy.settingsToTakeInAtLaunch(from: remote, over: mine, layouts: layouts, version: newer, local: synced)
        #expect(takenIn[seeded] as? Bool == true)
        #expect(isLayout(takenIn[layouts.other], third))
        #expect(takenIn[layouts.own] == nil)
        var older = newer
        older.modified = lastSynced.addingTimeInterval(-60)
        let fromOlder = Policy.settingsToTakeInAtLaunch(from: remote, over: mine, layouts: layouts, version: older, local: synced)
        #expect(fromOlder[seeded] as? Bool == true)
        #expect(fromOlder[layouts.other] == nil)
        #expect(Policy.otherLayoutToTakeIn(remote, over: mine, layouts: layouts, version: older, local: synced).isEmpty)
        #expect(!Policy.otherLayoutToTakeIn(remote, over: mine, layouts: layouts, version: newer, local: synced).isEmpty)
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
        func counts(byUser: Bool = true, _ onBar: [String: Int], saved: [String: Int]) -> Bool {
            Policy.sectionsToSave(byUser: byUser, onBar: onBar, saved: saved, beforeArrangement: nil).countsAsEdit
        }
        // A Command-click that moved nothing, with an item saved for the first time where
        // macOS put it.
        #expect(!counts(["a": 0, "b": 1, "new": 0], saved: before))
        #expect(!counts(before, saved: before))
        // A move of the user's.
        #expect(counts(["a": 0, "b": 2], saved: before))
        #expect(counts(["a": 1, "b": 1, "new": 0], saved: before))
        // holzBar's own saves never count.
        #expect(!counts(byUser: false, ["a": 0, "b": 2], saved: before))
        #expect(!counts([String: Int](), saved: [String: Int]()))
        // Every item is saved where it is; items not on the bar keep their saved section.
        let save = Policy.sectionsToSave(byUser: true, onBar: ["b": 2, "new": 0], saved: before, beforeArrangement: nil)
        #expect(save.sections == ["a": 0, "b": 2, "new": 0])
    }

    @Test("Before macOS 27, the bar before the user's arrangement tells the user's moves from macOS's")
    func sectionSaveWithBarBeforeArrangement() {
        let saved = ["moved": 0, "displaced": 0, "kept": 1]
        // macOS displaced `displaced` before the arrangement (a display change); the user then
        // moved `moved` and `unsaved`, an item without a saved section, and left `fresh` where
        // it is.
        let beforeArrangement = ["moved": 0, "displaced": 2, "kept": 1, "unsaved": 1, "fresh": 1]
        let onBar = ["moved": 1, "displaced": 2, "kept": 1, "unsaved": 0, "fresh": 1, "appeared": 2]
        let save = Policy.sectionsToSave(byUser: true, onBar: onBar, saved: saved, beforeArrangement: beforeArrangement)
        #expect(save.sections == ["moved": 1, "displaced": 0, "kept": 1, "unsaved": 0, "fresh": 1, "appeared": 2])
        #expect(save.countsAsEdit)
        // The first move of an item without a saved section counts.
        let firstMove = Policy.sectionsToSave(byUser: true, onBar: ["unsaved": 0], saved: [String: Int](), beforeArrangement: ["unsaved": 1])
        #expect(firstMove.sections == ["unsaved": 0])
        #expect(firstMove.countsAsEdit)
        // A Command-click after macOS displaced items saves none of them as the user's.
        let click = Policy.sectionsToSave(byUser: true, onBar: ["displaced": 2, "kept": 1], saved: saved, beforeArrangement: ["displaced": 2, "kept": 1])
        #expect(click.sections == saved)
        #expect(!click.countsAsEdit)
        // A displaced item the user moves back to its saved section is no change.
        let back = Policy.sectionsToSave(byUser: true, onBar: ["displaced": 0], saved: saved, beforeArrangement: ["displaced": 2])
        #expect(back.sections == saved)
        #expect(!back.countsAsEdit)
        // An item the user moved elsewhere counts.
        let elsewhere = Policy.sectionsToSave(byUser: true, onBar: ["displaced": 1], saved: saved, beforeArrangement: ["displaced": 2])
        #expect(elsewhere.sections["displaced"] == 1)
        #expect(elsewhere.countsAsEdit)
        // holzBar's own save ignores the record.
        let own = Policy.sectionsToSave(byUser: false, onBar: onBar, saved: saved, beforeArrangement: beforeArrangement)
        #expect(own.sections["displaced"] == 2)
        #expect(!own.countsAsEdit)
    }

    @Test("Before macOS 27, only a read the user cannot be arranging during records the bar before an arrangement")
    func barBeforeArrangementCapture() {
        #expect(Policy.capturesBarBeforeArrangement(isDragging: false, savesArrangementSoon: false, commandHeld: false, mouseButtonPressed: false))
        #expect(!Policy.capturesBarBeforeArrangement(isDragging: true, savesArrangementSoon: false, commandHeld: false, mouseButtonPressed: false))
        #expect(!Policy.capturesBarBeforeArrangement(isDragging: false, savesArrangementSoon: true, commandHeld: false, mouseButtonPressed: false))
        #expect(!Policy.capturesBarBeforeArrangement(isDragging: false, savesArrangementSoon: false, commandHeld: true, mouseButtonPressed: false))
        #expect(!Policy.capturesBarBeforeArrangement(isDragging: false, savesArrangementSoon: false, commandHeld: false, mouseButtonPressed: true))
    }

    @Test("Before macOS 27, holzBar's own placements never replace a section the user saved while the items moved")
    func ownPlacementsSpareUserSections() {
        // The reconciliation read no saved section for "new" and "left"; while it moved items,
        // the user dragged "left" to section 2, and that was saved.
        let placements = ["new": 0, "left": 1, "other": 1]
        let savedNow = ["left": 2, "known": 0]
        #expect(Policy.ownPlacementsToStore(placements, savedNow: savedNow, wanted: nil) == ["new": 0, "other": 1])
        // Items a profile places are saved by the profile.
        #expect(Policy.ownPlacementsToStore(placements, savedNow: savedNow, wanted: ["other": 2]) == ["new": 0])
        // Without a save in between, every placement is saved.
        #expect(Policy.ownPlacementsToStore(placements, savedNow: [:], wanted: nil) == placements)
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
