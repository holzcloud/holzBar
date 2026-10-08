//
//  ProfileSyncTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// Layout profiles sync per profile ID as `prof/<profileID>` on macOS 27 only (decision D-05, plan 28-09).
@Suite("SyncProfiles")
struct ProfileSyncTests {
    private typealias Fixtures = SyncFixtures

    private let table = SyncUnitTable.version1(normalizers: .canonical)
    private let macA = Fixtures.macA
    private let macB = Fixtures.macB
    private let work = SyncUnitKey.split(family: SyncUnitTable.profilesFamily, item: "P1")

    private func environment(_ generation: SyncGeneration = .g27) -> SyncEnvironment {
        Fixtures.environment(generation: generation, table: table)
    }

    private func workValue(name: String = "Work", sections: [String: Int] = ["com.a": 1], known: [String]? = ["com.b", "com.a"]) -> SyncValue {
        SyncLayout27.profileValue(name: name, applicationSections: sections, knownApplications: known)
    }

    private func state(_ registers: [SyncUnitKey: [SyncEntry]] = [:], local: [SyncUnitKey: SyncValue] = [:]) -> SyncState {
        var state = SyncState(mac: macA, nonce: "nonce-A", isEnabled: true)
        state.replica = Fixtures.replica(registers)
        state.session.snapshot = SyncSnapshot(values: local)
        state.session.ownFile = .absent
        return state
    }

    private func handle(_ event: SyncEvent, _ state: SyncState, _ generation: SyncGeneration = .g27) -> SyncStep {
        SyncEngine.handle(event, state: state, environment: environment(generation))
    }

    private func profilesData(_ profiles: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: profiles, options: [.sortedKeys])
    }

    // MARK: Intents

    @Test("Saving a profile is one intent for prof/<profileID> with its name, application sections and known applications")
    func savingIsOneIntent() throws {
        let stored = try profilesData([
            ["profileID": "P1", "name": "Work", "itemSections": ["x:y": 1], "applicationSections": ["com.a": 1], "knownApplications": ["com.b", "com.a"]],
        ])
        let projected = SyncProjection.snapshot(defaults: ["LayoutProfiles": stored], table: table, generation: .g27)
        let value = try #require(projected[work])
        // The helper builds exactly what the projection reads from the stored profile.
        #expect(value == workValue())
        let intents = SyncLayout27.profileIntents(old: [:], new: ["P1": value])
        #expect(intents == [SyncUnitIntent(unit: work, from: nil, to: .value(value))])
        let step = handle(.intent(.userSet(intents)), state())
        #expect(step.state.replica.live(work).map(\.payload) == [.value(value)])
    }

    @Test("Saving an unchanged profile yields no intent and mints nothing")
    func unchangedSaveYieldsNothing() {
        let value = workValue()
        #expect(SyncLayout27.profileIntents(old: ["P1": value], new: ["P1": value]).isEmpty)
        let step = handle(.intent(.userSet([SyncUnitIntent(unit: work, from: value, to: .value(value))])), state())
        #expect(step.state.replica.registers.isEmpty)
    }

    @Test("A rename is one change of one ID, never a deletion and a creation")
    func renameIsOneChange() throws {
        let before = workValue()
        let after = workValue(name: "Office")
        let intents = SyncLayout27.profileIntents(old: ["P1": before], new: ["P1": after])
        #expect(intents.count == 1)
        let intent = try #require(intents.first)
        #expect(intent.unit == work)
        #expect(intent.from == before)
        #expect(intent.to == .value(after))
        // The same sections travel with the new name.
        #expect(after.dictionaryValue?["applicationSections"] == before.dictionaryValue?["applicationSections"])
        // The group's entry is replaced, not joined by a second one.
        let theirs = Fixtures.entry(macB, 1, before)
        var held = state([work: [theirs]])
        held.applied[work] = [theirs.dot]
        let step = handle(.intent(.userSet(intents)), held)
        let live = step.state.replica.live(work)
        #expect(live.count == 1)
        #expect(live.first?.payload == .value(after))
    }

    @Test("Deleting a profile is a deletion intent, and a profile nobody published leaves no tombstone")
    func deletionIsADeletionIntent() throws {
        let value = workValue()
        let intents = SyncLayout27.profileIntents(old: ["P1": value], new: [:])
        #expect(intents == [SyncUnitIntent(unit: work, from: value, to: .deleted)])
        let theirs = Fixtures.entry(macB, 1, value)
        var held = state([work: [theirs]])
        held.applied[work] = [theirs.dot]
        let deleted = handle(.intent(.userSet(intents)), held)
        #expect(deleted.state.replica.live(work).map(\.payload) == [.deleted])
        let unpublished = handle(.intent(.userSet(intents)), state())
        #expect(unpublished.state.replica.registers.isEmpty)
    }

    // MARK: Generation scope

    @Test("A profile saved or renamed on macOS 26 creates no prof entry")
    func generation26CreatesNoProfileEntry() throws {
        let stored = try profilesData([["profileID": "P1", "name": "Work", "itemSections": ["x:y": 1], "applicationSections": [String: Int]()]])
        #expect(SyncProjection.snapshot(defaults: ["LayoutProfiles": stored], table: table, generation: .g26).isEmpty)
        let intent = SyncUnitIntent(unit: work, from: nil, to: .value(workValue()))
        let step = handle(.intent(.userSet([intent])), state(), .g26)
        #expect(step.state.replica.registers.isEmpty)
        let renamed = handle(.defaultsChanged(SyncSnapshot()), step.state, .g26)
        #expect(handle(.timer(.capture), renamed.state, .g26).state.replica.registers.isEmpty)
    }

    @Test("A profile hotkey syncs through the Hotkeys units like any hotkey; a key that names nothing is relayed")
    func profileHotkeySyncsLikeAnyHotkey() throws {
        let family = Defaults.Key.hotkeys.rawValue
        let hotkey = SyncUnitKey.split(family: family, item: "ApplyProfile:P1")
        let value = SyncValue.data(HotkeyStorage.encode(key: 18, modifiers: 8))
        let local = [hotkey: value]
        var held = state(local: local)
        held.baseline[hotkey] = .unset
        let captured = handle(.timer(.capture), held)
        #expect(captured.state.replica.live(hotkey).map(\.payload) == [.value(value)])
        #expect(table.descriptor(for: hotkey) != nil)
        #expect(table.descriptor(for: .split(family: family, item: "NoSuchAction:P1")) == nil)
    }

    // MARK: Conflicts

    @Test("Two Macs that created the same ID with different names in one window produce a conflict row labeled by name")
    func concurrentCreationIsAConflict() throws {
        let mine = Fixtures.entry(macA, 1, workValue(name: "Work"))
        let theirs = Fixtures.entry(macB, 1, workValue(name: "Home"))
        var held = state([work: [mine, theirs]], local: [work: workValue(name: "Work")])
        held.applied[work] = [mine.dot]
        let environment = environment()
        let plan = SyncPlan.plan(state: held, snapshot: held.session.snapshot ?? SyncSnapshot(), environment: environment)
        #expect(plan.outcomes[work] == .conflict(mine: true))
        let question = try #require(SyncEngine.question(for: held, scope: .mine, environment: environment))
        let row = try #require(question.rows.first { $0.unit == work })
        let names = (row.folder + [row.local].compactMap { $0 }).compactMap { value -> String? in
            if case .value(let synced) = value.value { synced.dictionaryValue?["name"]?.stringValue } else { nil }
        }
        #expect(names.sorted() == ["Home", "Work"])
    }

    @Test("A profile unit equal on both sides is silent")
    func equalProfileIsSilent() {
        let theirs = Fixtures.entry(macB, 1, workValue())
        let held = state([work: [theirs]], local: [work: workValue()])
        let plan = SyncPlan.plan(state: held, snapshot: held.session.snapshot ?? SyncSnapshot(), environment: environment())
        #expect(plan.outcomes[work] == .equal)
        #expect(SyncEngine.view(of: held, environment: environment()).hint == nil)
    }

    // MARK: Apply

    @Test("Applying a prof value keeps itemSections, bindings and unknown fields, end to end through the engine")
    func applyKeepsTheRestOfTheProfile() throws {
        let theirs = Fixtures.entry(macB, 1, workValue(name: "Office", sections: ["com.z": 2], known: ["com.z"]))
        let held = state([work: [theirs]], local: [work: workValue()])
        let step = handle(.command(.restart), held)
        var changes: [SyncUnitKey: SyncPayload] = [:]
        for effect in step.effects {
            if case .applyUnits(let applied) = effect {
                changes = applied
            }
        }
        #expect(changes[work] == .value(workValue(name: "Office", sections: ["com.z": 2], known: ["com.z"])))
        let stored = try profilesData([
            [
                "profileID": "P1", "name": "Work", "itemSections": ["x:y": 1], "applicationSections": ["com.a": 1],
                "knownApplications": ["com.a"], "displayUUID": "D", "spaceUUID": "S", "future": 1,
            ],
        ])
        let writes = SyncProjection.defaultsWrites(applying: changes, to: ["LayoutProfiles": stored], table: table)
        let data = try #require(writes["LayoutProfiles"] as? Data)
        let profiles = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let profile = try #require(profiles.first)
        #expect(profile["name"] as? String == "Office")
        #expect(profile["applicationSections"] as? [String: Int] == ["com.z": 2])
        #expect(profile["knownApplications"] as? [String] == ["com.z"])
        #expect(profile["itemSections"] as? [String: Int] == ["x:y": 1])
        #expect(profile["displayUUID"] as? String == "D")
        #expect(profile["spaceUUID"] as? String == "S")
        #expect(profile["future"] as? Int == 1)
    }

    @Test("A hostile profile value is refused and stays on its Mac")
    func hostileProfileIsRefused() {
        let hostile = SyncValue.dictionary(["name": .string(""), "applicationSections": .dictionary(["com.a": .integer(9)])])
        let intent = SyncUnitIntent(unit: work, from: nil, to: .value(hostile))
        let step = handle(.intent(.userSet([intent])), state())
        #expect(step.state.replica.registers.isEmpty)
        #expect(step.state.localOnly[work] == .invalid)
        let theirs = Fixtures.entry(macB, 1, hostile)
        let held = state([work: [theirs]])
        let plan = SyncPlan.plan(state: held, snapshot: held.session.snapshot ?? SyncSnapshot(), environment: environment())
        #expect(plan.outcomes[work] == .notApplicable)
        #expect(plan.fastForwardPayloads.isEmpty)
    }
}
