//
//  StateStoreTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncStateStore")
struct StateStoreTests {
    private typealias Fixtures = SyncFixtures

    /// A store over temporary support and caches folders that are removed when the body ends.
    private func withStore(_ body: (SyncStateStore, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "holzBar.tests.StateStore.\(UUID().uuidString)", directoryHint: .isDirectory)
        let support = root.appending(path: "Support", directoryHint: .isDirectory)
        let caches = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        defer {
            // A test may leave a folder read-only.
            _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support.appending(path: "holzBar/Sync").path(percentEncoded: false))
            try? FileManager.default.removeItem(at: root)
        }
        try body(SyncStateStore(supportDirectory: support, cachesDirectory: caches), support, caches)
    }

    private func state(counter: UInt64 = 3) -> SyncState {
        var state = Fixtures.state()
        let entry = Fixtures.entry(Fixtures.macA, counter, .string("value"))
        state.replica = Fixtures.replica([Fixtures.s1: [entry]])
        state.applied[Fixtures.s1] = [entry.dot]
        state.baseline[Fixtures.s1] = SyncValue.string("value").digest
        state.counter = counter
        state.publishedCounter = counter
        state.generation = 4
        return state
    }

    private func stateFile(_ support: URL) -> URL {
        support.appending(path: "holzBar/Sync/State.plist")
    }

    // MARK: State

    @Test("No file loads as missing, which the engine takes as no state")
    func missingFile() throws {
        try withStore { store, _, _ in
            #expect(store.load() == .missing)
            #expect(store.load().forEngine == .unreadable)
            #expect(!store.hasFile)
        }
    }

    @Test("A persisted state loads back as it was, under holzBar/Sync/State.plist of the support folder")
    func roundTrip() throws {
        try withStore { store, support, _ in
            let original = state()
            try store.persist(original)
            #expect(FileManager.default.fileExists(atPath: stateFile(support).path(percentEncoded: false)))
            guard case .read(.state(let loaded)) = store.load() else {
                Issue.record("the state did not load")
                return
            }
            #expect(loaded.replica == original.replica)
            #expect(loaded.counter == original.counter)
            #expect(loaded.generation == original.generation)
            #expect(loaded.mac == original.mac)
        }
    }

    @Test("A later persist replaces the file whole and leaves no temporary file")
    func replacesTheFile() throws {
        try withStore { store, support, _ in
            try store.persist(state(counter: 3))
            try store.persist(state(counter: 9))
            guard case .read(.state(let loaded)) = store.load() else {
                Issue.record("the state did not load")
                return
            }
            #expect(loaded.counter == 9)
            let names = try FileManager.default.contentsOfDirectory(atPath: stateFile(support).deletingLastPathComponent().path(percentEncoded: false))
            #expect(names == ["State.plist"])
        }
    }

    @Test("A failed write leaves the old file as it was")
    func failureLeavesTheOldFile() throws {
        try withStore { store, support, _ in
            try store.persist(state(counter: 3))
            let before = try Data(contentsOf: stateFile(support))
            let folder = stateFile(support).deletingLastPathComponent()
            // No file can be created in a folder that is read-only.
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
            #expect(throws: SyncStateStoreError.cannotWrite) {
                try store.persist(state(counter: 9))
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path(percentEncoded: false))
            #expect(try Data(contentsOf: stateFile(support)) == before)
        }
    }

    @Test("A file of a newer format reads as newer, is not rewritten, and a damaged file reads as unreadable")
    func newerAndDamagedFiles() throws {
        try withStore { store, support, _ in
            let file = stateFile(support)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let newer = try PropertyListSerialization.data(fromPropertyList: ["format": SyncState.currentFormat + 1, "future": "field"] as [String: Any], format: .binary, options: 0)
            try newer.write(to: file)
            #expect(store.load() == .read(.newerFormat(SyncState.currentFormat + 1)))
            #expect(throws: SyncStateStoreError.newerFormatOnDisk) {
                try store.persist(state())
            }
            #expect(try Data(contentsOf: file) == newer)

            try Data("damaged".utf8).write(to: file)
            #expect(store.load() == .read(.unreadable))
            // A damaged file is no evidence of a newer build: it is replaced.
            try store.persist(state())
            guard case .read(.state) = store.load() else {
                Issue.record("the damaged file was not replaced")
                return
            }
        }
    }

    // MARK: Counter floor

    @Test("The high-water file only grows, and it lives in the caches folder")
    func highWaterOnlyGrows() throws {
        try withStore { store, support, caches in
            #expect(store.highWater == 0)
            #expect(store.raiseHighWater(to: 40))
            #expect(store.highWater == 40)
            #expect(store.raiseHighWater(to: 25))
            #expect(store.highWater == 40)
            #expect(store.raiseHighWater(to: 41))
            #expect(store.highWater == 41)
            let file = caches.appending(path: "holzBar/Sync/CounterHighWater")
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text == "41")
            #expect(!FileManager.default.fileExists(atPath: support.appending(path: "holzBar/Sync/CounterHighWater").path(percentEncoded: false)))
        }
    }

    @Test("A damaged high-water file counts as zero and is raised over")
    func damagedHighWater() throws {
        try withStore { store, _, caches in
            let file = caches.appending(path: "holzBar/Sync/CounterHighWater")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not a number".utf8).write(to: file)
            #expect(store.highWater == 0)
            #expect(store.raiseHighWater(to: 7))
            #expect(store.highWater == 7)
        }
    }
}
