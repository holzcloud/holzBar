//
//  JoinLawsTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// A small deterministic generator. The simulator has its own; this suite stays independent.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@Suite("SyncJoinLaws")
struct JoinLawsTests {
    private static let seeds: UInt64 = 2000
    private let payloads: [SyncPayload] = [.value(.integer(0)), .value(.integer(1)), .value(.string("x")), .deleted]
    private let allKeys: [SyncUnitKey] = [
        .whole("A"), .whole("B"), .whole("C"),
        .split(family: "Hotkeys", item: "one"), .split(family: "Hotkeys", item: "two"), .split(family: "l27", item: "bundle:id/x"),
    ]

    private static func mac(_ index: Int) -> SyncMacID {
        let digit = Character(String(index, radix: 16, uppercase: true))
        func block(_ count: Int) -> String {
            String(repeating: digit, count: count)
        }
        guard let id = SyncMacID("\(block(8))-\(block(4))-\(block(4))-\(block(4))-\(block(12))") else {
            preconditionFailure("The test identity is malformed")
        }
        return id
    }

    /// The entry every replica holds for this dot, value and unit: the same entry everywhere, so
    /// equal dots with equal values are equal entries.
    private func entry(_ dot: SyncDot, _ payload: SyncPayload) -> SyncEntry {
        SyncEntry(dot: dot, at: Date(timeIntervalSinceReferenceDate: Double(dot.n) * 10), payload: payload)
    }

    /// A random replica in which every entry's dot is covered by the replica's own context.
    private func randomReplica(_ rng: inout SplitMix64, macs: [SyncMacID], keys: [SyncUnitKey]) -> SyncReplica {
        var counters: [SyncMacID: UInt64] = [:]
        for mac in macs {
            counters[mac] = UInt64.random(in: 0...6, using: &rng)
        }
        var registers: [SyncUnitKey: [SyncEntry]] = [:]
        for key in keys where Int.random(in: 0..<10, using: &rng) < 7 {
            var entries: [SyncEntry] = []
            for mac in macs {
                let limit = counters[mac] ?? 0
                guard limit > 0, Int.random(in: 0..<10, using: &rng) < 5 else {
                    continue
                }
                let dot = SyncDot(mac: mac, n: UInt64.random(in: 1...limit, using: &rng))
                entries.append(entry(dot, payloads[Int.random(in: 0..<payloads.count, using: &rng)]))
            }
            registers[key] = entries
        }
        let elements = ["a", "b", "c", "d"].filter { _ in Bool.random(using: &rng) }
        return SyncReplica(context: SyncContext(counters: counters), registers: registers, sets: ["S": elements])
    }

    private func randomSetup(_ rng: inout SplitMix64) -> (macs: [SyncMacID], keys: [SyncUnitKey]) {
        let macCount = Int.random(in: 2...4, using: &rng)
        let keyCount = Int.random(in: 1...6, using: &rng)
        return ((0..<macCount).map { Self.mac($0 + 10) }, Array(allKeys.prefix(keyCount)))
    }

    /// A true earlier state of `replica`: a lower context and exactly the entries it covers.
    private func older(_ replica: SyncReplica, _ rng: inout SplitMix64) -> SyncReplica {
        var counters: [SyncMacID: UInt64] = [:]
        for mac in replica.context.macs {
            counters[mac] = UInt64.random(in: 0...replica.context[mac], using: &rng)
        }
        let context = SyncContext(counters: counters)
        var registers: [SyncUnitKey: [SyncEntry]] = [:]
        for key in replica.keys {
            registers[key] = replica.live(key).filter { context.covers($0.dot) }
        }
        let sets = replica.sets.mapValues { $0.filter { _ in Bool.random(using: &rng) } }
        return SyncReplica(context: context, registers: registers, sets: sets)
    }

    private func join(_ lhs: SyncReplica, _ rhs: SyncReplica) -> SyncReplica {
        SyncReplica.join(lhs, rhs).replica
    }

    @Test("Joining is commutative")
    func commutative() async {
        await HeavyTestGate.run {
            for seed in 0..<Self.seeds {
                var rng = SplitMix64(state: seed)
                let (macs, keys) = randomSetup(&rng)
                let a = randomReplica(&rng, macs: macs, keys: keys)
                let b = randomReplica(&rng, macs: macs, keys: keys)
                let forward = SyncReplica.join(a, b)
                let backward = SyncReplica.join(b, a)
                #expect(forward.replica == backward.replica, "seed \(seed)")
                #expect(forward.collisions == backward.collisions, "seed \(seed)")
                #expect(forward.replica.digest == backward.replica.digest, "seed \(seed)")
            }
        }
    }

    @Test("Joining is associative")
    func associative() async {
        await HeavyTestGate.run {
            for seed in 0..<Self.seeds {
                var rng = SplitMix64(state: seed &+ 1_000_000)
                let (macs, keys) = randomSetup(&rng)
                let a = randomReplica(&rng, macs: macs, keys: keys)
                let b = randomReplica(&rng, macs: macs, keys: keys)
                let c = randomReplica(&rng, macs: macs, keys: keys)
                #expect(join(join(a, b), c) == join(a, join(b, c)), "seed \(seed)")
            }
        }
    }

    @Test("Joining is idempotent")
    func idempotent() async {
        await HeavyTestGate.run {
            for seed in 0..<Self.seeds {
                var rng = SplitMix64(state: seed &+ 2_000_000)
                let (macs, keys) = randomSetup(&rng)
                let a = randomReplica(&rng, macs: macs, keys: keys)
                let result = SyncReplica.join(a, a)
                #expect(result.replica == a, "seed \(seed)")
                #expect(result.collisions == SyncReplica.join(a, SyncReplica.empty).collisions, "seed \(seed)")
            }
        }
    }

    @Test("Joining a replica with an older copy of itself changes nothing")
    func olderCopy() async {
        await HeavyTestGate.run {
            for seed in 0..<Self.seeds {
                var rng = SplitMix64(state: seed &+ 3_000_000)
                let (macs, keys) = randomSetup(&rng)
                let x = randomReplica(&rng, macs: macs, keys: keys)
                let previous = older(x, &rng)
                #expect(join(x, previous) == x, "seed \(seed)")
                #expect(join(previous, x) == x, "seed \(seed)")
            }
        }
    }

    @Test("Contexts only grow")
    func contextsGrow() async {
        await HeavyTestGate.run {
            for seed in 0..<Self.seeds {
                var rng = SplitMix64(state: seed &+ 4_000_000)
                let (macs, keys) = randomSetup(&rng)
                let a = randomReplica(&rng, macs: macs, keys: keys)
                let b = randomReplica(&rng, macs: macs, keys: keys)
                let joined = join(a, b).context
                for mac in macs {
                    #expect(joined[mac] == max(a.context[mac], b.context[mac]), "seed \(seed)")
                }
            }
        }
    }

    @Test("Joining the intermediate states of one Mac in any order equals joining its last state")
    func coalescing() async {
        await HeavyTestGate.run {
            for seed in 0..<Self.seeds {
                var rng = SplitMix64(state: seed &+ 5_000_000)
                let (macs, keys) = randomSetup(&rng)
                // A real history: local changes that have seen the current entries, and ingested replicas.
                let me = macs[0]
                var counter: UInt64 = 0
                var states: [SyncReplica] = []
                var current = SyncReplica.empty
                for _ in 0..<Int.random(in: 2...4, using: &rng) {
                    if Bool.random(using: &rng) {
                        current = join(current, randomReplica(&rng, macs: Array(macs.dropFirst()), keys: keys))
                    } else if let key = keys.randomElement(using: &rng) {
                        counter = max(counter, current.context[me]) + 1
                        let dot = SyncDot(mac: me, n: counter)
                        current = current.setting(key, to: entry(dot, payloads[Int.random(in: 0..<payloads.count, using: &rng)]))
                    }
                    states.append(current)
                }
                guard let last = states.last else {
                    continue
                }
                for order in permutations(of: Array(states.indices)) {
                    let joined = order.dropFirst().reduce(states[order[0]]) { join($0, states[$1]) }
                    #expect(joined == last, "seed \(seed) order \(order)")
                }
            }
        }
    }

    private func permutations(of items: [Int]) -> [[Int]] {
        guard items.count > 1 else {
            return [items]
        }
        return items.indices.flatMap { index -> [[Int]] in
            var rest = items
            let head = rest.remove(at: index)
            return permutations(of: rest).map { [head] + $0 }
        }
    }

    // MARK: Specific cases

    private func replica(_ mac: SyncMacID, context: [SyncMacID: UInt64], entries: [SyncEntry], key: SyncUnitKey = .whole("U")) -> SyncReplica {
        SyncReplica(context: SyncContext(counters: context), registers: [key: entries])
    }

    @Test("An entry another replica has seen and no longer holds is removed; an unseen one survives")
    func coveredEntriesAreRemoved() {
        let macA = Self.mac(10)
        let macB = Self.mac(11)
        let old = entry(SyncDot(mac: macA, n: 2), .value(.integer(1)))
        let fresh = entry(SyncDot(mac: macA, n: 5), .value(.integer(2)))
        // B saw (A, 2) and replaced it with its own change; A has made (A, 5) since.
        let b = replica(macB, context: [macA: 2, macB: 1], entries: [entry(SyncDot(mac: macB, n: 1), .value(.integer(3)))])
        let a = replica(macA, context: [macA: 5], entries: [old, fresh])
        let joined = join(a, b).live(.whole("U"))
        #expect(joined.map(\.dot) == [SyncDot(mac: macA, n: 5), SyncDot(mac: macB, n: 1)])
    }

    @Test("The same dot with two different values keeps both and reports a collision")
    func collisionKeepsBoth() {
        let macA = Self.mac(10)
        let dot = SyncDot(mac: macA, n: 3)
        let x = replica(macA, context: [macA: 3], entries: [entry(dot, .value(.integer(1)))])
        let y = replica(macA, context: [macA: 3], entries: [entry(dot, .value(.integer(2)))])
        let result = SyncReplica.join(x, y)
        #expect(result.replica.live(.whole("U")).count == 2)
        #expect(result.collisions == [dot])
        #expect(result.replica.distinctValues(.whole("U")).count == 2)
        #expect(SyncReplica.join(y, x).replica == result.replica)
        // A third replica that has seen the dot and holds nothing for it does not hide the conflict by picking one.
        #expect(SyncReplica.join(x, x).collisions.isEmpty)
    }

    @Test("Concurrent changes both stay until a later change replaces them")
    func concurrentChanges() {
        let macA = Self.mac(10)
        let macB = Self.mac(11)
        let a = replica(macA, context: [macA: 1], entries: [entry(SyncDot(mac: macA, n: 1), .value(.integer(1)))])
        let b = replica(macB, context: [macB: 1], entries: [entry(SyncDot(mac: macB, n: 1), .value(.integer(2)))])
        let both = join(a, b)
        #expect(both.live(.whole("U")).count == 2)
        let resolved = both.setting(.whole("U"), to: entry(SyncDot(mac: macA, n: 2), .value(.integer(3))))
        #expect(join(resolved, a).live(.whole("U")).map(\.dot) == [SyncDot(mac: macA, n: 2)])
        #expect(join(resolved, b).live(.whole("U")).map(\.dot) == [SyncDot(mac: macA, n: 2)])
    }

    @Test("Entries equal in dot and value but different in date join to one entry, in both orders")
    func displayDateIsNotIdentity() {
        let macA = Self.mac(10)
        let dot = SyncDot(mac: macA, n: 1)
        let early = SyncEntry(dot: dot, at: Date(timeIntervalSinceReferenceDate: 1), payload: .value(.bool(true)))
        let late = SyncEntry(dot: dot, at: Date(timeIntervalSinceReferenceDate: 2), payload: .value(.bool(true)), extra: ["x": .integer(1)])
        let a = replica(macA, context: [macA: 1], entries: [early])
        let b = replica(macA, context: [macA: 1], entries: [late])
        #expect(SyncReplica.join(a, b).replica.live(.whole("U")).count == 1)
        #expect(SyncReplica.join(a, b).replica == SyncReplica.join(b, a).replica)
        #expect(SyncReplica.join(a, b).collisions.isEmpty)
    }

    @Test("A set above its cap keeps the elements with the smallest SHA-256 and joins as a lattice")
    func cappedSets() {
        let all = (0..<3000).map { "element\($0)" }
        let first = SyncReplica(sets: ["S": Array(all[0..<1800])])
        let second = SyncReplica(sets: ["S": Array(all[1200..<3000])])
        let third = SyncReplica(sets: ["S": Array(all[500..<2500])])
        let joined = join(first, second)
        #expect(joined.sets["S"]?.count == SyncDeviceFile.maximumSetElements)
        #expect(joined == join(second, first))
        #expect(join(joined, third) == join(first, join(second, third)))
        #expect(join(joined, joined) == joined)
        let expected = all
            .map { (SyncDigest.hash(Array($0.utf8)), $0) }
            .sorted { $0.0 < $1.0 }
            .prefix(SyncDeviceFile.maximumSetElements)
            .map(\.1)
        #expect(Set(joined.sets["S"] ?? []) == Set(expected))
    }
}
