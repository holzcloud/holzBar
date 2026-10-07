//
//  SyncTracerTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncTracer")
struct SyncTracerTests {
    private let macA = SyncMacID("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")
    private let macB = SyncMacID("BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")
    private let key = SyncUnitKey.whole("ShowOnHover")
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func replicas() throws -> (a: SyncReplica, b: SyncReplica) {
        let idA = try #require(macA)
        let idB = try #require(macB)
        let dotA = SyncDot(mac: idA, n: 5)
        let dotB = SyncDot(mac: idB, n: 7)
        let a = SyncReplica(
            context: SyncContext(counters: [idA: 5]),
            registers: [key: [SyncEntry(dot: dotA, at: date, payload: .value(.bool(true)))]]
        )
        // B saw A's change (A, 5), then wrote its own.
        let b = SyncReplica(
            context: SyncContext(counters: [idA: 5, idB: 7]),
            registers: [key: [SyncEntry(dot: dotB, at: date, payload: .value(.bool(false)))]]
        )
        return (a, b)
    }

    @Test("A change that saw the other change replaces it, in both join orders")
    func joinKeepsTheLaterChange() throws {
        let (a, b) = try replicas()
        let idB = try #require(macB)
        let forward = SyncReplica.join(a, b)
        let backward = SyncReplica.join(b, a)
        #expect(forward.replica == backward.replica)
        #expect(forward.collisions.isEmpty)
        let live = forward.replica.live(key)
        #expect(live.map(\.dot) == [SyncDot(mac: idB, n: 7)])
        #expect(live.map(\.payload) == [.value(.bool(false))])
    }

    @Test("A device file round-trips and joins to the same state")
    func deviceFileRoundTrip() throws {
        let (a, b) = try replicas()
        let idB = try #require(macB)
        let contents = SyncDeviceFile.Contents(
            unitTable: 1,
            mac: idB,
            installation: "nonce",
            written: date,
            replica: b
        )
        let data = try SyncDeviceFile.encode(contents)
        let decoded = try SyncDeviceFile.decode(data, fileName: "\(idB.rawValue).plist").get()
        #expect(decoded == contents)
        let joined = SyncReplica.join(a, decoded.replica).replica
        #expect(joined == SyncReplica.join(a, b).replica)
        #expect(joined.digest == SyncReplica.join(b, a).replica.digest)
        #expect(joined.live(key).map(\.payload) == [.value(.bool(false))])
    }
}
