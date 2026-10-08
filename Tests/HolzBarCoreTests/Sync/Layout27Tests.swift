//
//  Layout27Tests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// The rules of the macOS 27 families (plan 28-09): explicit values, intent-only capture, automatic stores,
/// joins, the upgrade from macOS 26, the union of the known applications and the profiles' generation scope.
@Suite("SyncLayout27")
struct Layout27Tests {
    private typealias Fixtures = SyncFixtures

    private let table = SyncUnitTable.version1(normalizers: .canonical)
    private let fresh = SyncFreshIdentity(mac: SyncMacID("DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!, nonce: "fresh-nonce")
    private let macA = Fixtures.macA
    private let macB = Fixtures.macB
    private let macC = Fixtures.macC
    private let bundleA = SyncUnitKey.split(family: SyncUnitTable.layout27Family, item: "com.a")
    private let bundleB = SyncUnitKey.split(family: SyncUnitTable.layout27Family, item: "com.b")
    private let known = SyncUnitTable.knownApplicationsSet

    // MARK: Builders

    private func environment(_ generation: SyncGeneration = .g27) -> SyncEnvironment {
        Fixtures.environment(generation: generation, freshIdentity: fresh, table: table)
    }

    private func profile(_ identifier: String) -> SyncUnitKey {
        .split(family: SyncUnitTable.profilesFamily, item: identifier)
    }

    /// An enabled, trusted state of Mac A that holds `registers` and the given local settings.
    private func state(
        _ registers: [SyncUnitKey: [SyncEntry]] = [:],
        local: [SyncUnitKey: SyncValue] = [:],
        known27: [String] = [],
        sets: [String: [String]] = [:]
    ) -> SyncState {
        var state = SyncState(mac: macA, nonce: "nonce-A", isEnabled: true)
        var replica = Fixtures.replica(registers)
        replica = SyncReplica(context: replica.context, registers: replica.registers, sets: sets)
        state.replica = replica
        state.session.snapshot = SyncSnapshot(values: local, known27: known27)
        state.session.ownFile = .absent
        return state
    }

    private func handle(_ event: SyncEvent, _ state: SyncState, _ generation: SyncGeneration = .g27) -> SyncStep {
        SyncEngine.handle(event, state: state, environment: environment(generation))
    }

    private func userSet(_ intents: [SyncUnitIntent]) -> SyncEvent {
        .intent(.userSet(intents))
    }

    private func entry(_ mac: SyncMacID, _ n: UInt64, _ value: SyncValue) -> SyncEntry {
        Fixtures.entry(mac, n, value)
    }

    private func plan(_ state: SyncState, _ generation: SyncGeneration = .g27) -> SyncPlan {
        SyncPlan.plan(state: state, snapshot: state.session.snapshot ?? SyncSnapshot(), environment: environment(generation))
    }

    private func view(_ state: SyncState, _ generation: SyncGeneration = .g27) -> SyncView {
        SyncEngine.view(of: state, environment: environment(generation))
    }

    private func schedules(_ step: SyncStep, _ timer: SyncTimer) -> Bool {
        step.effects.contains { if case .schedule(timer, _) = $0 { true } else { false } }
    }

    private func applies(_ step: SyncStep) -> [SyncUnitKey: SyncPayload] {
        for effect in step.effects {
            if case .applyUnits(let changes) = effect {
                return changes
            }
        }
        return [:]
    }

    private func knownApplied(_ step: SyncStep) -> [String]? {
        for effect in step.effects {
            if case .applyKnownApplications(let applications) = effect {
                return applications
            }
        }
        return nil
    }

    // MARK: Explicit values

    @Test("A move to Visible is the explicit value 0 and becomes an entry")
    func moveToVisibleIsExplicit() throws {
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(1), to: nil))
        #expect(intent.from == .integer(1))
        #expect(intent.to == .value(SyncLayout27.visible))
        let step = handle(userSet([intent]), state())
        let entries = step.state.replica.live(bundleA)
        #expect(entries.count == 1)
        #expect(entries.first?.payload == .value(.integer(0)))
        #expect(step.state.applied[bundleA] == entries.map(\.dot))
        #expect(schedules(step, .capture))
    }

    @Test("An entry that merely disappears from the defaults mints nothing")
    func disappearingEntryMintsNothing() {
        let mine = entry(macA, 1, .integer(1))
        var held = state([bundleA: [mine]], local: [:])
        held.applied[bundleA] = [mine.dot]
        held.baseline[bundleA] = SyncValue.integer(1).digest
        let step = handle(.timer(.capture), held)
        #expect(step.state.replica == held.replica)
        #expect(step.state.replica.live(bundleA).map(\.payload) == [.value(.integer(1))])
    }

    @Test("A local absent entry reads as visible: the folder's 0 is equal and adopted silently")
    func absentReadsAsVisible() {
        let theirs = entry(macB, 1, .integer(0))
        let held = state([bundleA: [theirs]], local: [:])
        #expect(plan(held).outcomes[bundleA] == .equal)
        #expect(view(held).hint == nil)
    }

    @Test("A group's section reaches a Mac that has no entry as a waiting fast-forward")
    func absentReceivesGroupValue() {
        let theirs = entry(macB, 1, .integer(2))
        let held = state([bundleA: [theirs]], local: [:])
        let outcome = plan(held)
        #expect(outcome.outcomes[bundleA] == .fastForward)
        #expect(outcome.fastForwardPayloads[bundleA] == .value(.integer(2)))
        #expect(view(held).hint == .restart)
    }

    // MARK: Intents

    @Test("layoutIntents gives one intent per changed application in sorted order, reading absence as visible")
    func layoutIntentsAreSorted() {
        let old: [String: SyncValue] = ["com.b": .integer(2), "com.a": .integer(1), "com.c": .integer(1)]
        let new: [String: SyncValue] = ["com.c": .integer(1), "com.d": .integer(1), "com.b": .integer(0)]
        let intents = SyncLayout27.layoutIntents(old: old, new: new)
        #expect(intents.map(\.unit) == [
            .split(family: "l27", item: "com.a"), .split(family: "l27", item: "com.b"), .split(family: "l27", item: "com.d"),
        ])
        #expect(intents.map(\.from) == [.integer(1), .integer(2), .integer(0)])
        #expect(intents.map(\.to) == [.value(.integer(0)), .value(.integer(0)), .value(.integer(1))])
    }

    @Test("A layout that does not change yields no intent, and a profile that changes nothing yields none")
    func unchangedLayoutYieldsNothing() {
        let layout: [String: SyncValue] = ["com.a": .integer(1), "com.b": .integer(2)]
        #expect(SyncLayout27.layoutIntents(old: layout, new: layout).isEmpty)
        #expect(SyncLayout27.layoutIntents(old: [:], new: ["com.a": .integer(0)]).isEmpty)
        #expect(SyncLayout27.moveIntent(bundleID: "com.a", from: nil, to: .integer(0)) == nil)
        #expect(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(1), to: .integer(1)) == nil)
    }

    @Test("A profile applied by a Space or display binding sends no intent: the capture mints nothing")
    func automaticStoreMintsNothing() {
        let held = state(local: [bundleA: .integer(1)])
        let changed = handle(.defaultsChanged(SyncSnapshot(values: [bundleA: .integer(2), bundleB: .integer(1)])), held)
        #expect(schedules(changed, .capture))
        let fired = handle(.timer(.capture), changed.state)
        #expect(fired.state.replica.registers.isEmpty)
        #expect(fired.state.counter == 0)
    }

    @Test("Import yields intents for the layout and the profiles: removed items become explicit 0 or a deletion")
    func importYieldsIntents() {
        let layout = SyncLayout27.layoutIntents(old: ["com.a": .integer(2)], new: ["com.b": .integer(1)])
        #expect(layout.map(\.to) == [.value(.integer(0)), .value(.integer(1))])
        let work = SyncLayout27.profileValue(name: "Work", applicationSections: ["com.a": 1], knownApplications: nil)
        let home = SyncLayout27.profileValue(name: "Home", applicationSections: [:], knownApplications: nil)
        let profiles = SyncLayout27.profileIntents(old: ["p1": work], new: ["p2": home])
        #expect(profiles.map(\.unit) == [profile("p1"), profile("p2")])
        #expect(profiles.map(\.to) == [.deleted, .value(home)])
    }

    @Test("protectedApplications lists exactly the bundle IDs with applied intent")
    func protectedApplications() {
        var held = state()
        held.applied[bundleA] = [SyncDot(mac: macA, n: 1)]
        held.applied[bundleB] = []
        held.applied[.split(family: SyncUnitTable.layout27Family, item: "com.c")] = [SyncDot(mac: macB, n: 2)]
        held.applied[profile("p1")] = [SyncDot(mac: macA, n: 3)]
        held.applied[.whole("ShowOnHover")] = [SyncDot(mac: macA, n: 4)]
        #expect(SyncLayout27.protectedApplications(in: held) == ["com.a", "com.c"])
        #expect(SyncLayout27.protectedApplications(in: state()).isEmpty)
    }

    @Test("Only the families l27 and prof are captured from intents")
    func intentCapturedFamilies() {
        #expect(SyncLayout27.isIntentCaptured(bundleA))
        #expect(SyncLayout27.isIntentCaptured(profile("p1")))
        #expect(!SyncLayout27.isIntentCaptured(.whole("ShowOnHover")))
        #expect(!SyncLayout27.isIntentCaptured(.split(family: "Hotkeys", item: "ShowHidden")))
    }

    @Test("A move that the group already holds adopts the entry and mints nothing")
    func moveToTheGroupsValueAdopts() throws {
        let theirs = entry(macB, 1, .integer(1))
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(0), to: .integer(1)))
        let step = handle(userSet([intent]), state([bundleA: [theirs]]))
        #expect(step.state.replica.live(bundleA) == [theirs])
        #expect(step.state.applied[bundleA] == [theirs.dot])
    }

    @Test("A move supersedes only the entries this Mac had applied")
    func moveSupersedesApplied() throws {
        let old = entry(macB, 1, .integer(1))
        var held = state([bundleA: [old]], local: [bundleA: .integer(1)])
        held.applied[bundleA] = [old.dot]
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(1), to: .integer(2)))
        let step = handle(userSet([intent]), held)
        let live = step.state.replica.live(bundleA)
        #expect(live.count == 1)
        #expect(live.first?.dot.mac == macA)
        #expect(live.first?.payload == .value(.integer(2)))
    }

    // MARK: Automatic stores

    @Test("A seeded or placed entry without applied intent is replaced silently by an incoming single value")
    func seededEntryFastForwards() {
        let theirs = entry(macB, 1, .integer(1))
        let held = state([bundleA: [theirs]], local: [bundleA: .integer(2)])
        #expect(plan(held).outcomes[bundleA] == .fastForward)
        #expect(plan(held).questionRows == 0)
        #expect(view(held).hint == .restart)
    }

    @Test("An incoming conflict between other Macs never involves a seeded entry")
    func seededEntryStaysOutOfConflicts() {
        let theirs = [entry(macB, 1, .integer(1)), entry(macC, 1, .integer(2))]
        let held = state([bundleA: theirs], local: [bundleA: .integer(0)])
        #expect(plan(held).outcomes[bundleA] == .conflict(mine: false))
        #expect(view(held).hint == nil)
    }

    @Test("A value that holzBar stored over an applied entry is no change of another Mac")
    func automaticDeviationFromAppliedIsSilent() {
        let mine = entry(macB, 1, .integer(1))
        var held = state([bundleA: [mine]], local: [bundleA: .integer(2)])
        held.applied[bundleA] = [mine.dot]
        #expect(plan(held).outcomes[bundleA] == .equal)
        #expect(view(held).hint == nil)
    }

    // MARK: Generation scope

    @Test("A macOS 26 Mac relays the macOS 27 families and neither compares, shows nor applies them")
    func generation26RelaysOnly() {
        let theirs = entry(macB, 1, .integer(2))
        let work = entry(macB, 2, SyncLayout27.profileValue(name: "Work", applicationSections: ["com.a": 1], knownApplications: nil))
        let held = state([bundleA: [theirs], profile("p1"): [work]], local: [:], sets: [known: ["com.x"]])
        let outcome = plan(held, .g26)
        #expect(outcome.outcomes[bundleA] == .relayOnly)
        #expect(outcome.outcomes[profile("p1")] == .relayOnly)
        #expect(outcome.fastForwardPayloads.isEmpty)
        #expect(outcome.questionRows == 0)
        let shown = view(held, .g26)
        #expect(shown.hint == nil)
        #expect(shown.lines.isEmpty)
        #expect(SyncEngine.question(for: held, scope: .mine, environment: environment(.g26)) == nil)
    }

    @Test("A macOS 26 Mac mints no dot for an intent of the macOS 27 families")
    func generation26MintsNothing() throws {
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(0), to: .integer(1)))
        let held = state()
        let step = handle(userSet([intent]), held, .g26)
        #expect(step.state.replica == held.replica)
        #expect(step.state.counter == 0)
    }

    @Test("A macOS 27 state restored on a macOS 26 Mac keeps every entry and set element in the file it writes")
    func downgradeKeepsEverything() throws {
        let theirs = entry(macB, 1, .integer(2))
        let work = entry(macB, 2, SyncLayout27.profileValue(name: "Work", applicationSections: ["com.a": 1], knownApplications: ["com.x"]))
        var held = state([bundleA: [theirs], profile("p1"): [work]], local: [:], sets: [known: ["com.x", "com.y"]])
        held.systemGeneration = .g27
        for event in [SyncEvent.defaultsChanged(SyncSnapshot()), .timer(.capture), .timer(.relay), .timer(.learned)] {
            held = handle(event, held, .g26).state
        }
        #expect(held.replica.live(bundleA) == [theirs])
        #expect(held.replica.live(profile("p1")) == [work])
        #expect(held.replica.sets[known] == ["com.x", "com.y"])
        guard case .write(let request) = SyncPublish.decision(state: held, environment: environment(.g26), trigger: .relay) else {
            Issue.record("The file was not written")
            return
        }
        #expect(request.contents.replica == held.replica)
    }

    // MARK: Joins

    private func joinStep(_ local: [SyncUnitKey: SyncValue], folder: [SyncUnitKey: [SyncEntry]]) -> SyncStep {
        var joiner = SyncState(mac: macA, nonce: "nonce-A", isEnabled: false)
        joiner.session.snapshot = SyncSnapshot(values: local)
        joiner.session.isTrusted = false
        let contents = SyncDeviceFile.Contents(unitTable: 1, mac: macB, installation: "nonce-B", written: Fixtures.now, replica: Fixtures.replica(folder))
        let read = SyncFolderRead(files: [SyncFileOutcome(macID: macB, size: 200, modified: Fixtures.now, state: .contents(contents))])
        let started = handle(.command(.turnOn("F1")), joiner)
        return handle(.folderRead(read, purpose: .join), started.state)
    }

    @Test("At a join a present entry that differs from the group's is protected and asked about")
    func joinAsksAboutAPresentEntry() {
        let step = joinStep([bundleA: .integer(2)], folder: [bundleA: [entry(macB, 1, .integer(1))]])
        #expect(step.state.pendingJoin?.phase == .asking)
        #expect(step.state.pendingJoin?.shown[bundleA] != nil)
    }

    @Test("At a join an absent entry takes the group's value silently and an equal entry is adopted")
    func joinTakesTheGroupsValueSilently() {
        let theirs = entry(macB, 1, .integer(1))
        let absent = joinStep([:], folder: [bundleA: [theirs]])
        #expect(absent.state.pendingJoin == nil)
        #expect(absent.state.isEnabled)
        #expect(plan(absent.state).outcomes[bundleA] == .fastForward)
        let equal = joinStep([bundleA: .integer(1)], folder: [bundleA: [theirs]])
        #expect(equal.state.pendingJoin == nil)
        #expect(equal.state.applied[bundleA] == [theirs.dot])
    }

    @Test("At a join an entry the group lacks is published as this Mac's")
    func joinPublishesAnEntryTheGroupLacks() {
        let step = joinStep([bundleA: .integer(2)], folder: [bundleB: [entry(macB, 1, .integer(1))]])
        #expect(step.state.pendingJoin == nil)
        let live = step.state.replica.live(bundleA)
        #expect(live.count == 1)
        #expect(live.first?.dot.mac == macA)
    }

    @Test("The join preview protects a value of the user's and not the visible section an absent entry reads as")
    func joinPreviewTable() {
        let folder: [SyncPayload] = [.value(.integer(1))]
        let env = environment()
        func preview(local: SyncValue?, hasValue: Bool, folder: [SyncPayload] = folder) -> SyncJoinPreview {
            SyncJoin.preview(unit: bundleA, local: local, folder: folder, legacy: nil, hasValue: hasValue, environment: env)
        }
        #expect(preview(local: .integer(0), hasValue: false) == .fastForward)
        #expect(preview(local: .integer(2), hasValue: true) == .row)
        #expect(preview(local: .integer(1), hasValue: true) == .adopt)
        #expect(preview(local: .integer(2), hasValue: true, folder: []) == .publish)
        #expect(preview(local: .integer(0), hasValue: false, folder: []) == .nothing)
        #expect(preview(local: .integer(0), hasValue: true, folder: [.value(.integer(0))]) == .adopt)
    }

    // MARK: Upgrade

    private let salt = Data("salt".utf8)

    private func launchInput(_ stored: SyncState, local: [SyncUnitKey: SyncValue], known27: [String] = []) -> SyncLaunchInput {
        SyncLaunchInput(
            snapshot: SyncSnapshot(values: local, known27: known27),
            stored: .state(stored),
            identity: SyncIdentityInput(
                storedID: macA.rawValue,
                storedHash: SettingsSyncDevice.hardwareHash(of: "HARDWARE-A", uid: 501, salt: salt),
                salt: salt,
                hardwareID: "HARDWARE-A",
                uid: 501
            ),
            defaultsGeneration: stored.generation,
            lastSyncedSeen: nil,
            syncIsOn: true,
            folder: "F1"
        )
    }

    private func upgraded(_ registers: [SyncUnitKey: [SyncEntry]], from: SyncGeneration? = .g26) -> SyncState {
        var held = state(registers)
        held.generation = 4
        held.baseline[.whole("ShowOnHover")] = .unset
        held.systemGeneration = from
        return held
    }

    @Test("After an upgrade from macOS 26 to 27 the group's arrangement arrives silently over seeded values")
    func upgradeTakesTheGroupsValuesSilently() {
        let theirs = entry(macB, 1, .integer(1))
        let stored = upgraded([bundleA: [theirs]])
        let step = handle(.launch(launchInput(stored, local: [bundleA: .integer(2), bundleB: .integer(1)])), SyncState(mac: macA, nonce: "ignored"))
        #expect(applies(step)[bundleA] == .value(.integer(1)))
        #expect(step.state.systemGeneration == .g27)
        // The seeded entry of an application the group knows nothing about stays unpublished and unasked.
        #expect(step.state.replica.live(bundleB).isEmpty)
        #expect(plan(step.state).questionRows == 0)
        #expect(view(step.state).hint == nil)
    }

    @Test("After an upgrade the seeded entries are automatic, and the state is never emptied")
    func upgradeMarksSeededEntriesAutomatic() {
        let theirs = entry(macB, 1, .integer(1))
        let stored = upgraded([bundleA: [theirs]])
        var noted = stored
        SyncLayout27.noteSystemGeneration(&noted, snapshot: SyncSnapshot(values: [bundleA: .integer(2), bundleB: .integer(1)]), environment: environment())
        #expect(noted.localOrigin[bundleA] == .automatic)
        #expect(noted.localOrigin[bundleB] == .automatic)
        #expect(noted.systemGeneration == .g27)
        #expect(noted.replica == stored.replica)
        // A launch on the same generation changes nothing.
        var again = noted
        SyncLayout27.noteSystemGeneration(&again, snapshot: SyncSnapshot(values: [bundleA: .integer(2)]), environment: environment())
        #expect(again == noted)
    }

    @Test("After an upgrade only an application the user arranged since can conflict")
    func upgradeConflictsOnlyOnNewIntent() throws {
        let theirs = [entry(macB, 1, .integer(1)), entry(macB, 2, .integer(1))]
        var held = upgraded([bundleA: [theirs[0]], bundleB: [theirs[1]]])
        SyncLayout27.noteSystemGeneration(&held, snapshot: SyncSnapshot(values: [bundleA: .integer(2), bundleB: .integer(2)]), environment: environment())
        held.session.snapshot = SyncSnapshot(values: [bundleA: .integer(2), bundleB: .integer(2)])
        #expect(plan(held).questionRows == 0)
        // The user moves com.b after the upgrade: that application has a new entry beside the group's.
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.b", from: .integer(2), to: .integer(1)))
        let moved = handle(userSet([intent]), held).state
        #expect(moved.localOrigin[bundleB] == nil)
        #expect(plan(moved).outcomes[bundleA] == .fastForward)
        #expect(plan(moved).outcomes[bundleB] == .equal)
    }

    // MARK: Known applications

    @Test("A learned application joins the set without a dot, and a learned-only change waits for the timer")
    func learnedApplicationJoinsTheSet() {
        let held = state(local: [:], known27: [])
        let learned = handle(.defaultsChanged(SyncSnapshot(known27: ["com.x", "com.y"])), held)
        #expect(learned.state.replica.sets[known] == ["com.x", "com.y"])
        #expect(learned.state.replica.registers.isEmpty)
        #expect(learned.state.counter == 0)
        #expect(schedules(learned, .learned))
        #expect(!schedules(learned, .capture))
        // The timer is pending: a further learned application schedules nothing new.
        let more = handle(.defaultsChanged(SyncSnapshot(known27: ["com.x", "com.y", "com.z"])), learned.state)
        #expect(more.state.replica.sets[known] == ["com.x", "com.y", "com.z"])
        #expect(!schedules(more, .learned))
        // The hour publishes it.
        let fired = handle(.timer(.learned), more.state)
        #expect(fired.effects.contains { if case .writeOwnFile = $0 { true } else { false } })
        #expect(!fired.state.session.isLearnedTimerPending)
    }

    @Test("A learned application rides along with the next write")
    func learnedApplicationRidesAlong() throws {
        let held = state(local: [:], known27: [])
        let learned = handle(.defaultsChanged(SyncSnapshot(values: [.whole("ShowOnHover"): .bool(true)], known27: ["com.x"])), held)
        #expect(schedules(learned, .capture))
        var base = learned.state
        base.baseline[.whole("ShowOnHover")] = .unset
        let fired = handle(.timer(.capture), base)
        let request = try #require(fired.effects.compactMap { effect -> SyncWriteRequest? in
            if case .writeOwnFile(let request) = effect { request } else { nil }
        }.first)
        #expect(request.contents.replica.sets[known] == ["com.x"])
        #expect(request.contents.replica.live(.whole("ShowOnHover")).count == 1)
    }

    @Test("The union is applied at launch and at Restart only, and never as a hint, a question or a restart")
    func unionIsAppliedAtLaunchAndRestartOnly() {
        var held = state(local: [:], known27: ["com.x"], sets: [known: ["com.x", "com.z"]])
        held.systemGeneration = .g27
        // A change of the defaults, a timer and a folder read apply nothing.
        for event in [SyncEvent.defaultsChanged(SyncSnapshot(known27: ["com.x"])), .timer(.capture), .timer(.relay), .folderRead(SyncFolderRead(), purpose: .check)] {
            #expect(knownApplied(handle(event, held)) == nil)
        }
        #expect(view(held).hint == nil)
        #expect(SyncEngine.question(for: held, scope: .mine, environment: environment()) == nil)
        // Restart carries it, and the launch does too.
        let restart = handle(.command(.restart), held)
        #expect(knownApplied(restart) == ["com.z"])
        #expect(restart.effects.contains { if case .relaunch = $0 { true } else { false } })
        held.generation = 3
        var stored = held
        stored.session = SyncSession()
        let launch = handle(.launch(launchInput(stored, local: [:], known27: ["com.x"])), SyncState(mac: macA, nonce: "ignored"))
        #expect(knownApplied(launch) == ["com.z"])
        #expect(view(launch.state).hint == nil)
    }

    @Test("A macOS 26 Mac never adds to or applies the known applications")
    func generation26NeverTouchesKnownApplications() {
        let held = state(local: [:], known27: ["com.x"], sets: [known: ["com.z"]])
        let changed = handle(.defaultsChanged(SyncSnapshot(known27: ["com.x", "com.y"])), held, .g26)
        #expect(changed.state.replica.sets[known] == ["com.z"])
        #expect(!schedules(changed, .learned))
        #expect(knownApplied(handle(.command(.restart), held, .g26)) == nil)
    }

    // MARK: Queued intents and the state

    @Test("An intent made while the state cannot mint waits and is minted when it can")
    func intentWaitsForATrustedState() throws {
        var held = state()
        held.session.isTrusted = false
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(0), to: .integer(1)))
        let queued = handle(userSet([intent]), held)
        #expect(queued.state.replica.registers.isEmpty)
        #expect(queued.state.session.queuedIntents == [intent])
        var trusted = queued.state
        trusted.session.isTrusted = true
        let fired = handle(.timer(.capture), trusted)
        #expect(fired.state.session.queuedIntents.isEmpty)
        #expect(fired.state.replica.live(bundleA).map(\.payload) == [.value(.integer(1))])
    }

    @Test("A value the user set is no longer automatic")
    func userIntentClearsTheAutomaticMark() throws {
        var held = state()
        held.localOrigin[bundleA] = .automatic
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(0), to: .integer(1)))
        #expect(handle(userSet([intent]), held).state.localOrigin[bundleA] == nil)
    }

    @Test("A move made while sync is off is a present value of the user's: the plan asks where the group moved on")
    func moveWhileOffIsAPresentValue() throws {
        // The group's newer section is waiting, this Mac applied the older one, and the user moves the app while sync is off.
        let older = entry(macB, 1, .integer(1))
        let newer = entry(macB, 2, .integer(2))
        var held = state([bundleA: [newer]], local: [bundleA: .integer(0)])
        held.isEnabled = false
        held.applied[bundleA] = [older.dot]
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(1), to: .integer(0)))
        let step = handle(userSet([intent]), held)
        // Nothing is minted while sync is off, and the value is marked as the user's.
        #expect(step.state.replica == held.replica)
        #expect(step.state.localOrigin[bundleA] == .preexisting)
        // With sync on again the plan asks about it instead of replacing it at Restart.
        var again = step.state
        again.isEnabled = true
        #expect(plan(again).outcomes[bundleA] == .preRow)
        #expect(plan(again).fastForwardPayloads[bundleA] == nil)
    }

    @Test("A move made while sync is off by a Mac that does not author the unit marks nothing")
    func moveWhileOffOnMacOS26MarksNothing() throws {
        var held = state()
        held.isEnabled = false
        let intent = try #require(SyncLayout27.moveIntent(bundleID: "com.a", from: .integer(0), to: .integer(1)))
        #expect(handle(userSet([intent]), held, .g26).state.localOrigin.isEmpty)
    }

    @Test("The macOS generation of the last launch round-trips through Sigma and is absent in older files")
    func systemGenerationRoundTrips() throws {
        for generation in [SyncGeneration?.none, .g26, .g27] {
            var held = SyncState(mac: macA, nonce: "n")
            held.systemGeneration = generation
            guard case .state(let decoded) = SyncStateCodec.decode(try SyncStateCodec.encode(held)) else {
                Issue.record("The state did not decode")
                return
            }
            #expect(decoded.systemGeneration == generation)
        }
        // A file written before the field existed decodes without it.
        let data = try SyncStateCodec.encode(SyncState(mac: macA, nonce: "n"))
        var root = try #require(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
        root["systemGeneration"] = nil
        let older = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        guard case .state(let decoded) = SyncStateCodec.decode(older) else {
            Issue.record("The older state did not decode")
            return
        }
        #expect(decoded.systemGeneration == nil)
    }
}
