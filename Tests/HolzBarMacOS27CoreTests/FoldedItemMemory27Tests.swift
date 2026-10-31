//
//  FoldedItemMemory27Tests.swift
//  holzBar
//

import CoreGraphics
import Foundation
import Testing
@testable import HolzBarMacOS27Core

@Suite("FoldedItemMemory27")
struct FoldedItemMemory27Tests {
    private typealias Memory = FoldedItemMemory27<String>

    private let bar = CGRect(x: 0, y: 0, width: 1512, height: 33)

    private func candidate(_ id: UInt32, pid: pid_t = 100, x: CGFloat = 1000, payload: String = "") -> Memory.Candidate {
        Memory.Candidate(windowID: id, ownerPID: pid, frame: CGRect(x: x, y: 4, width: 24, height: 24), payload: payload)
    }

    private func memory(seen: [Memory.Candidate]) -> Memory {
        var memory = Memory()
        memory.update(seen: seen, controlPresent: true, running: [100, 200], displayID: 1, displayBounds: bar)
        return memory
    }

    @Test("an item missing from the next read is kept while the control is there and its process runs")
    func keptWhileControlPresent() {
        var memory = memory(seen: [candidate(1), candidate(2, pid: 200)])
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100, 200], displayID: 1, displayBounds: bar)
        #expect(memory.folded.map(\.windowID) == [2])
        // Still kept on the read after, with nothing new to say.
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100, 200], displayID: 1, displayBounds: bar)
        #expect(memory.folded.map(\.windowID) == [2])
    }

    @Test("nothing is kept when the control is gone")
    func droppedWithoutControl() {
        var memory = memory(seen: [candidate(1), candidate(2)])
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.map(\.windowID) == [2])
        memory.update(seen: [candidate(1)], controlPresent: false, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.isEmpty)
        // And it does not come back when the control returns.
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.isEmpty)
    }

    @Test("an item whose process quit is dropped")
    func droppedWhenProcessGone() {
        var memory = memory(seen: [candidate(1), candidate(2, pid: 200)])
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100, 200], displayID: 1, displayBounds: bar)
        #expect(memory.folded.map(\.windowID) == [2])
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.isEmpty)
    }

    @Test("a fresh read of a kept item replaces it and it is no longer listed as folded")
    func freshReplacesKept() {
        var memory = memory(seen: [candidate(1), candidate(2, payload: "old")])
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.count == 1)
        memory.update(seen: [candidate(1), candidate(2, x: 500, payload: "new")], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.isEmpty)
        // It folds again later: the remembered one is the fresh one.
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.map(\.payload) == ["new"])
    }

    @Test("an expanded bar lists no item twice")
    func noDuplicateWhenExpanded() {
        var memory = memory(seen: [candidate(1), candidate(2)])
        memory.update(seen: [candidate(1)], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        // Expanded: the control is there and the folded item is drawn again.
        memory.update(seen: [candidate(1), candidate(2, x: 300)], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.isEmpty)
    }

    @Test("an owner whose query timed out keeps its items")
    func timeoutKeepsItems() {
        var memory = memory(seen: [candidate(1, pid: 200)])
        // The read had no answer from pid 200 (skipped or timed out), which still runs.
        memory.update(seen: [], controlPresent: true, running: [100, 200], displayID: 1, displayBounds: bar)
        #expect(memory.folded.map(\.windowID) == [1])
    }

    @Test("items that were not on the display are not remembered")
    func displayBounds() {
        var memory = Memory()
        let elsewhere = candidate(2, x: 5000)
        memory.update(seen: [candidate(1), elsewhere], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        memory.update(seen: [], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.map(\.windowID) == [1])
    }

    @Test("a change of the active display forgets what was kept")
    func displayChange() {
        var memory = memory(seen: [candidate(1)])
        memory.update(seen: [], controlPresent: true, running: [100], displayID: 2, displayBounds: bar)
        #expect(memory.folded.isEmpty)
    }

    @Test("the memory is bounded")
    func bounded() {
        var memory = Memory()
        let many = (0..<500).map { candidate(UInt32($0)) }
        memory.update(seen: many, controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        memory.update(seen: [], controlPresent: true, running: [100], displayID: 1, displayBounds: bar)
        #expect(memory.folded.count == Memory.limit)
    }
}
