//
//  CounterTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncCounter")
struct CounterTests {
    private let now: UInt64 = 1_800_000_000

    @Test("The counter is above every floor and at least the unix seconds")
    func aboveEveryFloor() {
        #expect(SyncIdentity.nextCounter(stateCounter: 5, mirror: 3, highWater: 4, unixSeconds: now, maxSeenSelf: 2) == now)
        #expect(SyncIdentity.nextCounter(stateCounter: now + 10, mirror: 3, highWater: 4, unixSeconds: now, maxSeenSelf: 2) == now + 11)
        #expect(SyncIdentity.nextCounter(stateCounter: 5, mirror: now + 20, highWater: 4, unixSeconds: now, maxSeenSelf: 2) == now + 21)
        #expect(SyncIdentity.nextCounter(stateCounter: 5, mirror: 3, highWater: now + 30, unixSeconds: now, maxSeenSelf: 2) == now + 31)
        #expect(SyncIdentity.nextCounter(stateCounter: 5, mirror: 3, highWater: 4, unixSeconds: now, maxSeenSelf: now + 40) == now + 41)
    }

    @Test("Two counters in the same second differ")
    func sameSecond() throws {
        let first = try #require(SyncIdentity.nextCounter(stateCounter: 0, mirror: 0, highWater: 0, unixSeconds: now, maxSeenSelf: 0))
        let second = try #require(SyncIdentity.nextCounter(stateCounter: first, mirror: first, highWater: first, unixSeconds: now, maxSeenSelf: 0))
        #expect(second == first + 1)
    }

    @Test("A counter above 2^34 is refused")
    func cap() {
        #expect(SyncIdentity.nextCounter(stateCounter: SyncDeviceFile.maximumCounter - 1, mirror: 0, highWater: 0, unixSeconds: now, maxSeenSelf: 0) == SyncDeviceFile.maximumCounter)
        #expect(SyncIdentity.nextCounter(stateCounter: SyncDeviceFile.maximumCounter, mirror: 0, highWater: 0, unixSeconds: now, maxSeenSelf: 0) == nil)
        #expect(SyncIdentity.nextCounter(stateCounter: 0, mirror: 0, highWater: 0, unixSeconds: SyncDeviceFile.maximumCounter + 1, maxSeenSelf: 0) == nil)
        #expect(SyncIdentity.nextCounter(stateCounter: .max, mirror: 0, highWater: 0, unixSeconds: now, maxSeenSelf: 0) == nil)
    }

    @Test("A clock set back two days and a restored state never repeat a counter")
    func clockStepsBackAndStateRestored() throws {
        var used = Set<UInt64>()
        var mirror: UInt64 = 0
        var highWater: UInt64 = 0
        var stateCounter: UInt64 = 0
        var maxSeen: UInt64 = 0
        var clock = now
        // Normal use, with Sigma persisted after every counter.
        var oldState: UInt64 = 0
        for step in 0..<5 {
            let next = try #require(SyncIdentity.nextCounter(stateCounter: stateCounter, mirror: mirror, highWater: highWater, unixSeconds: clock, maxSeenSelf: maxSeen))
            #expect(used.insert(next).inserted)
            stateCounter = next
            mirror = next
            highWater = next
            if step == 1 {
                oldState = next
            }
            clock += 1
        }
        // The clock steps back two days and Sigma is restored from a backup: the mirror in the
        // defaults and the high-water mark in the caches still carry the counters used.
        clock -= 2 * 86400
        stateCounter = oldState
        for _ in 0..<5 {
            let next = try #require(SyncIdentity.nextCounter(stateCounter: stateCounter, mirror: mirror, highWater: highWater, unixSeconds: clock, maxSeenSelf: maxSeen))
            #expect(used.insert(next).inserted, "counter \(next) was used before")
            stateCounter = next
            mirror = next
            highWater = next
            clock += 1
        }
        // The mirror and the caches are lost too: the highest own counter seen in a file
        // (this Mac's own file) is the last floor.
        maxSeen = used.max() ?? 0
        mirror = 0
        highWater = 0
        stateCounter = 0
        let next = try #require(SyncIdentity.nextCounter(stateCounter: stateCounter, mirror: mirror, highWater: highWater, unixSeconds: clock, maxSeenSelf: maxSeen))
        #expect(used.insert(next).inserted)
        #expect(next > maxSeen)
    }
}
