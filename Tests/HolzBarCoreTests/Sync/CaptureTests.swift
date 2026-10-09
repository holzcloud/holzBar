//
//  CaptureTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// Builders for the engine tests: three Macs, a small permissive unit table, states, entries and
/// environments written by hand.
enum SyncFixtures {
    static let macA = SyncMacID("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    static let macB = SyncMacID("BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
    static let macC = SyncMacID("CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static let s1 = SyncUnitKey.whole("S1")
    static let s2 = SyncUnitKey.whole("S2")
    static let small = SyncUnitKey.whole("Small")
    static let only27 = SyncUnitKey.whole("Only27")
    static func item(_ name: String) -> SyncUnitKey { .split(family: "Fam", item: name) }

    static func descriptor(
        _ name: String,
        isFamily: Bool = false,
        cap: Int = 1 << 10,
        scope: SyncGeneration? = nil
    ) -> SyncUnitDescriptor {
        SyncUnitDescriptor(
            name: name,
            storedKeys: [],
            cap: cap,
            maximumItems: isFamily ? SyncDeviceFile.maximumEntriesPerFamily : nil,
            scope: scope,
            isSet: false,
            isFamily: isFamily,
            measure: { $0.encodedSize },
            // A value of the text "bad" is not valid for any unit.
            validate: { _, value in value != .string("bad") }
        )
    }

    /// Whole units `S1`, `S2`, `Small` (16 bytes), `Only27` (macOS 27 only) and the family `Fam`.
    static let table = SyncUnitTable(
        version: 1,
        descriptors: [
            descriptor("S1"), descriptor("S2"), descriptor("Small", cap: 16), descriptor("Only27", scope: .g27),
            descriptor("Fam", isFamily: true),
        ]
    )

    static func environment(
        generation: SyncGeneration = .g27,
        unixSeconds: UInt64 = 1_000,
        floors: SyncCounterFloors = SyncCounterFloors(),
        guards: SyncGuards = .all,
        freshIdentity: SyncFreshIdentity? = nil,
        table: SyncUnitTable = SyncFixtures.table,
        now: Date = SyncFixtures.now
    ) -> SyncEnvironment {
        SyncEnvironment(
            table: table,
            generation: generation,
            now: now,
            unixSeconds: unixSeconds,
            counterFloors: floors,
            guards: guards,
            freshIdentity: freshIdentity
        )
    }

    /// An enabled, trusted state of `mac` whose units all have the baseline "unset".
    static func state(_ mac: SyncMacID = macA, baseline: [SyncUnitKey: SyncDigest] = [s1: .unset, s2: .unset, small: .unset, only27: .unset]) -> SyncState {
        var state = SyncState(mac: mac, nonce: "nonce-\(mac.rawValue.prefix(1))", isEnabled: true)
        state.baseline = baseline
        return state
    }

    static func entry(_ mac: SyncMacID, _ n: UInt64, _ value: SyncValue?) -> SyncEntry {
        SyncEntry(dot: SyncDot(mac: mac, n: n), at: now, payload: value.map { .value($0) } ?? .deleted)
    }

    /// A replica whose context covers every given entry.
    static func replica(_ registers: [SyncUnitKey: [SyncEntry]], extraContext: [SyncMacID: UInt64] = [:]) -> SyncReplica {
        var counters = extraContext
        for entries in registers.values {
            for entry in entries {
                counters[entry.dot.mac] = max(counters[entry.dot.mac] ?? 0, entry.dot.n)
            }
        }
        return SyncReplica(context: SyncContext(counters: counters), registers: registers)
    }

    static func snapshot(_ values: [SyncUnitKey: SyncValue] = [:], aliased: Set<SyncUnitKey> = []) -> SyncSnapshot {
        SyncSnapshot(values: values, aliased: aliased)
    }

    /// The state after it holds `entries` as applied, with `baseline` their value.
    static func applying(_ state: SyncState, _ key: SyncUnitKey, _ entry: SyncEntry, value: SyncValue?) -> SyncState {
        var state = state
        state.replica = replica(
            state.replica.registers.merging([key: [entry]]) { _, new in new },
            extraContext: Dictionary(uniqueKeysWithValues: state.replica.context.macs.map { ($0, state.replica.context[$0]) })
        )
        state.applied[key] = [entry.dot]
        state.baseline[key] = value?.digest ?? .unset
        return state
    }
}

@Suite("SyncCapture")
struct CaptureTests {
    private typealias Fixtures = SyncFixtures

    private func capture(_ values: [SyncUnitKey: SyncValue], state: SyncState, environment: SyncEnvironment? = nil, aliased: Set<SyncUnitKey> = []) -> SyncState {
        SyncCapture.capture(Fixtures.snapshot(values, aliased: aliased), state: state, environment: environment ?? Fixtures.environment())
    }

    @Test("A value whose digest equals the baseline mints nothing")
    func unchangedMintsNothing() {
        var state = Fixtures.state()
        state.baseline[Fixtures.s1] = SyncValue.string("same").digest
        let result = capture([Fixtures.s1: .string("same")], state: state)
        #expect(result == state)
    }

    @Test("A changed value mints exactly one entry above every counter floor")
    func changeMintsOneEntry() {
        let state = Fixtures.state()
        let floors = SyncCounterFloors(mirror: 5_000, highWater: 7_000)
        let result = capture(
            [Fixtures.s1: .string("new")],
            state: state,
            environment: Fixtures.environment(unixSeconds: 1_000, floors: floors)
        )
        let live = result.replica.live(Fixtures.s1)
        #expect(live.count == 1)
        let entry = live[0]
        #expect(entry.dot.mac == Fixtures.macA)
        #expect(entry.dot.n > 7_000)
        #expect(entry.payload == .value(.string("new")))
        #expect(result.counter == entry.dot.n)
        #expect(result.applied[Fixtures.s1] == [entry.dot])
        #expect(result.baseline[Fixtures.s1] == SyncValue.string("new").digest)
        #expect(result.replica.context[Fixtures.macA] == entry.dot.n)
        #expect(result.replica.registers.count == 1)
    }

    @Test("The counter stays above the state's counter, the highest own counter seen and the clock")
    func counterStaysAboveEveryFloor() {
        var state = Fixtures.state()
        state.counter = 40
        state.replica = Fixtures.replica([:], extraContext: [Fixtures.macA: 90])
        let result = capture([Fixtures.s1: .string("x")], state: state, environment: Fixtures.environment(unixSeconds: 10))
        #expect(result.replica.live(Fixtures.s1)[0].dot.n == 91)
        let later = capture([Fixtures.s1: .string("x"), Fixtures.s2: .string("y")], state: result, environment: Fixtures.environment(unixSeconds: 5_000))
        #expect(later.replica.live(Fixtures.s2)[0].dot.n == 5_000)
    }

    @Test("A change supersedes only the dots this Mac had applied, so a waiting entry of another Mac stays live")
    func supersedesOnlyAppliedDots() {
        var state = Fixtures.state()
        let mine = Fixtures.entry(Fixtures.macA, 10, .string("mine"))
        let theirs = Fixtures.entry(Fixtures.macB, 20, .string("theirs"))
        state.replica = Fixtures.replica([Fixtures.s1: [mine, theirs]])
        state.applied[Fixtures.s1] = [mine.dot]
        state.baseline[Fixtures.s1] = SyncValue.string("mine").digest
        let result = capture([Fixtures.s1: .string("changed")], state: state)
        let live = result.replica.live(Fixtures.s1)
        #expect(live.count == 2)
        #expect(live.contains { $0.dot == theirs.dot })
        #expect(!live.contains { $0.dot == mine.dot })
        #expect(result.replica.distinctValues(Fixtures.s1).count == 2)
    }

    @Test("A change also supersedes this Mac's own earlier entries that the defaults already carried, which a Sigma restored alone does not know as applied")
    func supersedesOwnEntriesTheDefaultsCarried() {
        var state = Fixtures.state()
        let old = Fixtures.entry(Fixtures.macA, 10, .string("old"))
        let later = Fixtures.entry(Fixtures.macA, 50, .string("later"))
        let theirs = Fixtures.entry(Fixtures.macB, 20, .string("theirs"))
        state.replica = Fixtures.replica([Fixtures.s1: [old, later, theirs]])
        state.baseline[Fixtures.s1] = SyncValue.string("old").digest
        // The mirror in the defaults says counter 40 was minted when they were last written: the old entry was carried, the later
        // one was not, and another Mac's entry never is.
        let environment = Fixtures.environment(floors: SyncCounterFloors(mirror: 40))
        let result = capture([Fixtures.s1: .string("changed")], state: state, environment: environment)
        let live = result.replica.live(Fixtures.s1)
        #expect(!live.contains { $0.dot == old.dot })
        #expect(live.contains { $0.dot == later.dot })
        #expect(live.contains { $0.dot == theirs.dot })
        #expect(live.count == 3)
    }

    @Test("Without the applied-context guard a change supersedes every live entry")
    func withoutAppliedContextGuard() {
        var state = Fixtures.state()
        let theirs = Fixtures.entry(Fixtures.macB, 20, .string("theirs"))
        state.replica = Fixtures.replica([Fixtures.s1: [theirs]])
        let guarded = capture([Fixtures.s1: .string("changed")], state: state)
        #expect(guarded.replica.live(Fixtures.s1).count == 2)
        let control = capture(
            [Fixtures.s1: .string("changed")],
            state: state,
            environment: Fixtures.environment(guards: SyncGuards.all.subtracting(.appliedContext))
        )
        #expect(control.replica.live(Fixtures.s1).count == 1)
        #expect(control.replica.live(Fixtures.s1)[0].dot.mac == Fixtures.macA)
    }

    @Test("A removed key mints a deletion only when the unit had a value, and a key never present mints nothing")
    func deletionNeedsABaselineValue() {
        var state = Fixtures.state()
        state.baseline[Fixtures.s1] = SyncValue.string("had").digest
        let removed = capture([:], state: state)
        #expect(removed.replica.live(Fixtures.s1).map(\.payload) == [.deleted])
        #expect(removed.baseline[Fixtures.s1] == .unset)
        #expect(removed.replica.live(Fixtures.s2).isEmpty)

        // S2 was never present: nothing is minted for it, with or without a baseline of unset.
        #expect(capture([:], state: Fixtures.state()) == Fixtures.state())
        var noBaseline = Fixtures.state()
        noBaseline.baseline[Fixtures.s2] = nil
        #expect(capture([:], state: noBaseline) == noBaseline)
    }

    @Test("Without the absent-means-no-value guard an absent unit another Mac set is captured as a deletion")
    func withoutAbsentGuard() {
        var state = Fixtures.state()
        state.baseline[Fixtures.s2] = nil
        state.replica = Fixtures.replica([Fixtures.s2: [Fixtures.entry(Fixtures.macB, 7, .string("theirs"))]])
        #expect(capture([:], state: state) == state)
        let control = capture(
            [:],
            state: state,
            environment: Fixtures.environment(guards: SyncGuards.all.subtracting(.absentMeansNoValue))
        )
        #expect(control.replica.live(Fixtures.s2).count == 2)
        #expect(control.replica.live(Fixtures.s2).contains { $0.payload == .deleted })
    }

    @Test("A unit with no baseline is never captured: it is marked as there before sync")
    func unitWithoutBaselineIsPreexisting() {
        var state = Fixtures.state()
        state.baseline[Fixtures.s1] = nil
        let result = capture([Fixtures.s1: .string("present")], state: state)
        #expect(result.replica.live(Fixtures.s1).isEmpty)
        #expect(result.localOrigin[Fixtures.s1] == .preexisting)
        #expect(result.baseline[Fixtures.s1] == nil)
        #expect(result.counter == 0)
    }

    @Test("An invalid value is local only and mints nothing, and a valid small value clears it")
    func invalidValueIsLocalOnly() {
        let state = Fixtures.state()
        let invalid = capture([Fixtures.s1: .string("bad")], state: state)
        #expect(invalid.localOnly[Fixtures.s1] == .invalid)
        #expect(invalid.baseline[Fixtures.s1] == SyncValue.string("bad").digest)
        #expect(invalid.replica.live(Fixtures.s1).isEmpty)
        let valid = capture([Fixtures.s1: .string("good")], state: invalid)
        #expect(valid.localOnly[Fixtures.s1] == nil)
        #expect(valid.replica.live(Fixtures.s1).count == 1)
    }

    @Test("A value that cannot be represented is invalid and local only")
    func unrepresentableValueIsInvalid() {
        let result = capture([Fixtures.s1: SyncProjection.unrepresentable], state: Fixtures.state())
        #expect(result.localOnly[Fixtures.s1] == .invalid)
        #expect(result.replica.live(Fixtures.s1).isEmpty)
    }

    @Test("An oversize value is local only, mints nothing and is cleared when a small value returns")
    func oversizeValueIsLocalOnly() {
        let big = SyncValue.string(String(repeating: "x", count: 64))
        let result = capture([Fixtures.small: big], state: Fixtures.state())
        #expect(result.localOnly[Fixtures.small] == .oversize)
        #expect(result.baseline[Fixtures.small] == big.digest)
        #expect(result.replica.live(Fixtures.small).isEmpty)
        let small = capture([Fixtures.small: .string("ok")], state: result)
        #expect(small.localOnly[Fixtures.small] == nil)
        #expect(small.replica.live(Fixtures.small).count == 1)
    }

    @Test("When the local value equals the single live value, applied takes its dots and nothing is minted")
    func finishedApplyAdoptsDots() {
        var state = Fixtures.state()
        let theirs = Fixtures.entry(Fixtures.macB, 20, .string("theirs"))
        state.replica = Fixtures.replica([Fixtures.s1: [theirs]])
        let result = capture([Fixtures.s1: .string("theirs")], state: state)
        #expect(result.applied[Fixtures.s1] == [theirs.dot])
        #expect(result.baseline[Fixtures.s1] == SyncValue.string("theirs").digest)
        #expect(result.replica == state.replica)
        #expect(result.counter == 0)
    }

    @Test("An aliased unit is neither captured as a deletion nor applied, and the new key is an ordinary entry")
    func aliasedUnitIsRelayOnly() {
        var state = Fixtures.state()
        let old = Fixtures.item("ns:Title")
        let new = Fixtures.item("ns:#1")
        state.baseline[old] = SyncValue.string("icon").digest
        // The item is gone from its old key and present under the new one.
        let result = capture([new: .string("icon")], state: state, aliased: [old])
        #expect(result.replica.live(old).isEmpty)
        #expect(result.baseline[old] == SyncValue.string("icon").digest)
        #expect(result.replica.live(new).map(\.payload) == [.value(.string("icon"))])
    }

    @Test("A new item of a family is captured, because a family is known whole")
    func newFamilyItemIsCaptured() {
        let item = Fixtures.item("OpenItem:x")
        let result = capture([item: .string("combo")], state: Fixtures.state())
        #expect(result.replica.live(item).map(\.payload) == [.value(.string("combo"))])
        #expect(result.applied[item]?.count == 1)
    }

    @Test("A unit that only macOS 27 authors is not captured on macOS 26")
    func scopedUnitIsNotCapturedElsewhere() {
        let state = Fixtures.state()
        let on26 = capture([Fixtures.only27: .string("v")], state: state, environment: Fixtures.environment(generation: .g26))
        #expect(on26.replica.live(Fixtures.only27).isEmpty)
        let on27 = capture([Fixtures.only27: .string("v")], state: state)
        #expect(on27.replica.live(Fixtures.only27).count == 1)
    }

    @Test("A unit this build does not know is never captured")
    func unknownUnitIsNotCaptured() {
        let state = Fixtures.state()
        let result = capture([.whole("FromTheFuture"): .string("v")], state: state)
        #expect(result == state)
    }

    @Test("A counter above 2^34 mints nothing and marks the unit invalid")
    func counterLimit() {
        var state = Fixtures.state()
        state.counter = SyncDeviceFile.maximumCounter
        let result = capture([Fixtures.s1: .string("v")], state: state)
        #expect(result.replica.live(Fixtures.s1).isEmpty)
        #expect(result.localOnly[Fixtures.s1] == .invalid)
        #expect(result.counter == SyncDeviceFile.maximumCounter)
    }

    @Test("An untrusted state mints nothing, unless the trusted-state guard is removed")
    func untrustedStateMintsNothing() {
        var state = Fixtures.state()
        state.session.isTrusted = false
        #expect(capture([Fixtures.s1: .string("v")], state: state) == state)
        let control = capture(
            [Fixtures.s1: .string("v")],
            state: state,
            environment: Fixtures.environment(guards: SyncGuards.all.subtracting(.trustedState))
        )
        #expect(control.replica.live(Fixtures.s1).count == 1)
    }

    @Test("A value two builds normalize differently but digest equal after normalization mints nothing")
    func normalizedValuesCompareEqual() throws {
        let table = SyncUnitTable.version1(normalizers: .canonical)
        let key = Defaults.Key.menuBarAppearanceConfigurationV2.rawValue
        let stored = try #require(#"{"b":1,"a":2}"#.data(using: .utf8))
        let rewritten = try #require(#"{"a":2,"b":1}"#.data(using: .utf8))
        let environment = Fixtures.environment(table: table)
        let first = SyncProjection.snapshot(defaults: [key: stored], table: table, generation: .g27)
        let second = SyncProjection.snapshot(defaults: [key: rewritten], table: table, generation: .g27)
        var state = Fixtures.state(baseline: [.whole(key): try #require(first[.whole(key)]).digest])
        state.baseline[.whole(key)] = first[.whole(key)]?.digest
        let result = SyncCapture.capture(SyncSnapshot(values: second), state: state, environment: environment)
        #expect(result == state)
    }
}
