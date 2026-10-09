//
//  FolderAccessTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncFolderAccess")
struct FolderAccessTests {
    private typealias Fixtures = SyncFixtures

    private let unit = SyncUnitKey.whole("ShowOnHover")

    // MARK: Builders

    /// A temporary sync folder that is removed when the body ends.
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "holzBar.tests.FolderAccess.\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func macs(in folder: URL) -> URL {
        folder.appending(path: "holzBar/Macs", directoryHint: .isDirectory)
    }

    private func contents(of mac: SyncMacID, value: Bool = true, counter: UInt64 = 5) -> SyncDeviceFile.Contents {
        let entry = SyncEntry(dot: SyncDot(mac: mac, n: counter), at: Fixtures.now, payload: .value(.bool(value)))
        let replica = SyncReplica(context: SyncContext(counters: [mac: counter]), registers: [unit: [entry]])
        return SyncDeviceFile.Contents(unitTable: 1, mac: mac, installation: "nonce", written: Fixtures.now, replica: replica)
    }

    private func put(_ mac: SyncMacID, in folder: URL, value: Bool = true, modified: Date? = nil) throws {
        try put(data: try SyncDeviceFile.encode(contents(of: mac, value: value)), named: "\(mac.rawValue).plist", in: folder, modified: modified)
    }

    private func put(data: Data, named name: String, in folder: URL, modified: Date? = nil) throws {
        let directory = macs(in: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false))
        }
    }

    private func read(
        _ folder: URL,
        purpose: SyncReadPurpose = .check,
        known: [SyncMacID] = [],
        maximumFiles: Int = 64,
        legacy: SyncLegacyRequest? = nil,
        isDownloaded: @escaping (URL) -> Bool = { _ in true },
        deadline: ContinuousClock.Instant? = nil
    ) -> SyncFolderRead {
        SyncFolderReader.read(
            syncFolder: folder,
            purpose: purpose,
            knownMacs: known,
            isDownloaded: isDownloaded,
            deadline: deadline,
            legacy: legacy,
            maximumFiles: maximumFiles
        )
    }

    private func listing(of folder: URL) -> [String] {
        let paths = FileManager.default.enumerator(atPath: folder.path(percentEncoded: false))?.allObjects as? [String] ?? []
        return paths.sorted()
    }

    // MARK: Listing

    @Test("The listing keeps device file names only, and a missing Macs folder is a folder without files")
    func listingFiltersNames() throws {
        try withFolder { folder in
            #expect(read(folder).files.isEmpty)
            try put(Fixtures.macA, in: folder)
            try put(data: Data([1]), named: ".DS_Store", in: folder)
            try put(data: Data([1]), named: "Icon\r", in: folder)
            try put(data: Data([1]), named: ".\(Fixtures.macB.rawValue).tmp", in: folder)
            try put(data: Data([1]), named: "notes.plist", in: folder)
            try put(data: Data([1]), named: "\(Fixtures.macB.rawValue.lowercased()).plist", in: folder)
            let result = read(folder)
            #expect(result.availability == .available)
            #expect(result.files.map(\.macID) == [Fixtures.macA])
            guard case .contents(let file)? = result.files.first?.state else {
                Issue.record("the device file was not read")
                return
            }
            #expect(file.replica.live(unit).map(\.payload) == [.value(.bool(true))])
        }
    }

    @Test("A folder that does not exist is unavailable and nothing is created")
    func missingFolderIsUnavailable() throws {
        try withFolder { folder in
            let missing = folder.appending(path: "gone", directoryHint: .isDirectory)
            #expect(read(missing).availability == .unavailable)
            #expect(!FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))
        }
    }

    @Test("At most 64 files are read, the most recently modified first and then by name")
    func listingCapsAtTheLimit() throws {
        try withFolder { folder in
            var ids: [SyncMacID] = []
            for index in 0..<70 {
                let uuid = UUID(uuid: (UInt8(index), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15))
                ids.append(SyncMacID(uuid))
            }
            for (index, mac) in ids.enumerated() {
                // The first six are the oldest, the others get the same date, so the name orders them.
                let modified = Date(timeIntervalSinceReferenceDate: 700_000_000 + (index < 6 ? Double(index) : 1_000))
                try put(mac, in: folder, modified: modified)
            }
            let result = read(folder)
            #expect(result.files.count == 64)
            #expect(result.skipped == 6)
            let readMacs = Set(result.files.compactMap(\.macID))
            for old in ids.prefix(6) {
                #expect(!readMacs.contains(old))
            }
            let smaller = read(folder, maximumFiles: 3)
            #expect(smaller.files.count == 3)
            #expect(Set(smaller.files.compactMap(\.macID)) == Set(ids[6..<9]))
        }
    }

    // MARK: Refusals

    @Test("A symbolic link, a folder, a file over 1 MiB and a damaged file are refused, never read")
    func refusals() throws {
        try withFolder { folder in
            let outside = folder.appending(path: "outside.plist")
            try Data("secret".utf8).write(to: outside)
            let directory = macs(in: folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let link = Fixtures.macA
            try FileManager.default.createSymbolicLink(at: directory.appending(path: "\(link.rawValue).plist"), withDestinationURL: outside)
            let folderMac = Fixtures.macB
            try FileManager.default.createDirectory(at: directory.appending(path: "\(folderMac.rawValue).plist"), withIntermediateDirectories: true)
            let large = Fixtures.macC
            try put(data: Data(count: SyncDeviceFile.maximumReadSize + 1), named: "\(large.rawValue).plist", in: folder)
            let damaged = SyncMacID(UUID(uuid: (9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9)))
            try put(data: Data("not a plist".utf8), named: "\(damaged.rawValue).plist", in: folder)
            let result = read(folder)
            func state(of mac: SyncMacID) -> SyncFileState? {
                result.files.first { $0.macID == mac }?.state
            }
            #expect(state(of: link) == .refused(.symbolicLink))
            #expect(state(of: folderMac) == .refused(.notRegularFile))
            #expect(state(of: large) == .refused(.tooLarge(SyncDeviceFile.maximumReadSize + 1)))
            #expect(state(of: damaged) == .refused(.notPropertyList))
        }
    }

    @Test("A name that is not the Mac the file holds is refused whole")
    func nameMismatchIsRefused() throws {
        try withFolder { folder in
            // The file of Mac B under the name of Mac A.
            try put(data: try SyncDeviceFile.encode(contents(of: Fixtures.macB)), named: "\(Fixtures.macA.rawValue).plist", in: folder)
            #expect(read(folder).files.first?.state == .refused(.nameMismatch))
        }
    }

    @Test("A link or a file where holzBar or Macs must be folder makes the folder unusable")
    func linkedFoldersAreUnusable() throws {
        try withFolder { folder in
            let elsewhere = folder.appending(path: "elsewhere", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: elsewhere.appending(path: "Macs"), withIntermediateDirectories: true)
            let root = folder.appending(path: "root", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appending(path: "holzBar"), withDestinationURL: elsewhere)
            #expect(read(root).availability == .unusable)

            let other = folder.appending(path: "other", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: other.appending(path: "holzBar"), withIntermediateDirectories: true)
            try Data().write(to: other.appending(path: "holzBar/Macs"))
            #expect(read(other).availability == .unusable)

            let linkedMacs = folder.appending(path: "linked", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: linkedMacs.appending(path: "holzBar"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: linkedMacs.appending(path: "holzBar/Macs"), withDestinationURL: elsewhere)
            #expect(read(linkedMacs).availability == .unusable)
        }
    }

    // MARK: Names and states

    @Test("A conflict copy of a known Mac yields its owner and is never read")
    func conflictCopyYieldsOwner() throws {
        try withFolder { folder in
            try put(Fixtures.macA, in: folder)
            try put(data: Data("anything".utf8), named: "\(Fixtures.macA.rawValue) (conflicted copy).plist", in: folder)
            try put(data: Data("anything".utf8), named: "\(Fixtures.macC.rawValue) (1).plist", in: folder)
            let result = read(folder, known: [Fixtures.macA, Fixtures.macB])
            let copies = result.files.filter { $0.macID == nil }
            #expect(copies.map(\.state) == [.conflictCopy(owner: Fixtures.macA)])
            #expect(result.files.filter { $0.macID == Fixtures.macA }.count == 1)
        }
    }

    @Test("A file that is not downloaded is dataless and not read, and a read past its deadline leaves the rest pending")
    func datalessAndDeadline() throws {
        try withFolder { folder in
            try put(Fixtures.macA, in: folder)
            try put(Fixtures.macB, in: folder)
            let dataless = read(folder) { $0.lastPathComponent != "\(Fixtures.macA.rawValue).plist" }
            #expect(dataless.files.first { $0.macID == Fixtures.macA }?.state == .dataless)
            guard case .contents? = dataless.files.first(where: { $0.macID == Fixtures.macB })?.state else {
                Issue.record("the downloaded file was not read")
                return
            }
            let late = read(folder, deadline: ContinuousClock.now - .seconds(1))
            #expect(late.files.map(\.state) == [.pending, .pending])
        }
    }

    // MARK: The legacy file

    @Test("The legacy file is read only when the purpose or the engine asks, and a metadata request drops its settings")
    func legacyIsReadOnRequest() throws {
        try withFolder { folder in
            let plist: [String: Any] = [
                SettingsSyncFile.modifiedKey: Fixtures.now,
                SettingsSyncDevice.deviceIDKey: "OLD-ID",
                SettingsSyncFile.settingsKey: ["ShowOnHover": true],
            ]
            try FileManager.default.createDirectory(at: folder.appending(path: "holzBar"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: folder.appending(path: "holzBar/Settings.plist"))
            #expect(read(folder).legacy == nil)
            guard case .file(let metadata)? = read(folder, legacy: .metadata).legacy else {
                Issue.record("no metadata")
                return
            }
            #expect(metadata.settings.isEmpty)
            #expect(metadata.deviceID == "OLD-ID")
            guard case .file(let joined)? = read(folder, purpose: .join).legacy else {
                Issue.record("a join reads the settings")
                return
            }
            #expect(joined.settings["ShowOnHover"] == .bool(true))
            #expect(read(folder, legacy: SyncLegacyRequest.none).legacy == nil)
        }
    }

    // MARK: Writing

    @Test("The writer creates exactly Macs/<MacID>.plist and leaves every other file as it was")
    func writerWritesOnlyTheOwnFile() throws {
        try withFolder { folder in
            let holzBar = folder.appending(path: "holzBar", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: holzBar, withIntermediateDirectories: true)
            let legacy = holzBar.appending(path: "Settings.plist")
            try Data("legacy".utf8).write(to: legacy)
            let date = Date(timeIntervalSinceReferenceDate: 600_000_000)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: legacy.path(percentEncoded: false))
            try Data("user file".utf8).write(to: folder.appending(path: "Other.txt"))
            let before = listing(of: folder)

            let result = SyncFolderWriter.write(contents(of: Fixtures.macA), syncFolder: folder, expecting: .absent, counter: 5)
            guard case .verified(let receipt) = result else {
                Issue.record("not verified: \(result)")
                return
            }
            #expect(receipt.counter == 5)
            #expect(receipt.replicaDigest == receipt.fileDigest)
            let created = Set(listing(of: folder)).subtracting(before)
            #expect(created == ["holzBar/Macs", "holzBar/Macs/\(Fixtures.macA.rawValue).plist"])
            #expect(try Data(contentsOf: legacy) == Data("legacy".utf8))
            #expect(try legacy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == date)
            #expect(try Data(contentsOf: folder.appending(path: "Other.txt")) == Data("user file".utf8))
            let back = read(folder)
            #expect(back.files.map(\.macID) == [Fixtures.macA])
        }
    }

    @Test("The writer does not create the sync folder, and refuses a link or a file where holzBar must be")
    func writerNeedsAnExistingFolder() throws {
        try withFolder { folder in
            let missing = folder.appending(path: "gone", directoryHint: .isDirectory)
            #expect(SyncFolderWriter.write(contents(of: Fixtures.macA), syncFolder: missing, expecting: .absent) == .failed(.unavailable))
            #expect(!FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))

            let elsewhere = folder.appending(path: "elsewhere", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            let root = folder.appending(path: "root", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appending(path: "holzBar"), withDestinationURL: elsewhere)
            #expect(SyncFolderWriter.write(contents(of: Fixtures.macA), syncFolder: root, expecting: .absent) == .failed(.unavailable))
            #expect(listing(of: elsewhere).isEmpty)
        }
    }

    @Test("The writer replaces the own file only when it is what the session read, and leaves no temporary file")
    func writerChecksTheExpectation() throws {
        try withFolder { folder in
            let first = contents(of: Fixtures.macA, value: true)
            guard case .verified(let receipt) = SyncFolderWriter.write(first, syncFolder: folder, expecting: .absent) else {
                Issue.record("the first write failed")
                return
            }
            // An own file that exists is not "absent".
            let second = contents(of: Fixtures.macA, value: false, counter: 6)
            #expect(SyncFolderWriter.write(second, syncFolder: folder, expecting: .absent) == .failed(.ownFileChanged))
            // A file that is not the one the session read.
            let stale = SyncDigest.unset
            #expect(SyncFolderWriter.write(second, syncFolder: folder, expecting: .readThisSession(digest: stale)) == .failed(.ownFileChanged))
            // The file the session read is replaced.
            let replaced = SyncFolderWriter.write(second, syncFolder: folder, expecting: .readThisSession(digest: receipt.fileDigest), counter: 6)
            guard case .verified(let second) = replaced else {
                Issue.record("not verified: \(replaced)")
                return
            }
            #expect(second.counter == 6)
            #expect(second.fileDigest != receipt.fileDigest)
            #expect(listing(of: folder) == ["holzBar", "holzBar/Macs", "holzBar/Macs/\(Fixtures.macA.rawValue).plist"])
        }
    }

    @Test("A file over the limit is not written and the previous file stays")
    func oversizeIsNotWritten() throws {
        try withFolder { folder in
            guard case .verified(let receipt) = SyncFolderWriter.write(contents(of: Fixtures.macA), syncFolder: folder, expecting: .absent) else {
                Issue.record("the first write failed")
                return
            }
            var large = contents(of: Fixtures.macA, counter: 6)
            let entry = SyncEntry(dot: SyncDot(mac: Fixtures.macA, n: 6), at: Fixtures.now, payload: .value(.data(Data(count: SyncDeviceFile.maximumWriteSize))))
            large.replica = SyncReplica(context: SyncContext(counters: [Fixtures.macA: 6]), registers: [unit: [entry]])
            #expect(SyncFolderWriter.write(large, syncFolder: folder, expecting: .readThisSession(digest: receipt.fileDigest)) == .failed(.tooLarge))
            let back = read(folder)
            guard case .contents(let file)? = back.files.first?.state else {
                Issue.record("the own file is gone")
                return
            }
            #expect(file.replica.digest == receipt.fileDigest)
        }
    }

    // MARK: Tracer

    @Test("Two Macs exchange a setting through real files")
    func twoMacsExchangeASetting() throws {
        try withFolder { folder in
            // The legacy file of 0.0.7-beta1 is in the folder, holding the setting both Macs will end with.
            let legacy = folder.appending(path: "holzBar/Settings.plist")
            try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
            let legacyBytes = try PropertyListSerialization.data(
                fromPropertyList: [
                    SettingsSyncFile.modifiedKey: Fixtures.now,
                    SettingsSyncDevice.deviceIDKey: "THE-BETA1-MAC",
                    SettingsSyncFile.settingsKey: ["ShowOnHover": true],
                ] as [String: Any],
                format: .xml,
                options: 0
            )
            try legacyBytes.write(to: legacy)
            let legacyDate = Date(timeIntervalSinceReferenceDate: 600_000_000)
            try FileManager.default.setAttributes([.modificationDate: legacyDate], ofItemAtPath: legacy.path(percentEncoded: false))

            try TracerMac.with(name: "A", folder: folder, hardware: "HARDWARE-A", uid: 501) { macA in
                // Mac A comes from the pause: a stored id, a bookmark, a hash without the user ID, bookkeeping of 0.0.7-beta1, sync on.
                let oldID = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
                let salt = Data("salt".utf8)
                let lastSynced = Date(timeIntervalSinceReferenceDate: 650_000_000)
                macA.defaults.set(true, forKey: "SyncsSettingsWithICloud")
                macA.defaults.set(true, forKey: "ShowOnHover")
                macA.defaults.set(oldID, forKey: "SettingsSyncDeviceID")
                macA.defaults.set(salt, forKey: "SettingsSyncDeviceSalt")
                macA.defaults.set(SettingsSyncDevice.hardwareHash(of: "HARDWARE-A", salt: salt), forKey: "SettingsSyncDeviceHash")
                macA.defaults.set(Data([1, 2, 3]), forKey: "SettingsSyncFolderBookmark")
                macA.defaults.set(lastSynced, forKey: "SettingsSyncLastSynced")
                macA.defaults.set("base-digest", forKey: "SettingsSyncBaseSettingsDigest")
                macA.defaults.set("layout-digest", forKey: "SettingsSyncBaseLayoutDigest")
                macA.defaults.set(3, forKey: "SettingsSyncLayoutEdits")
                macA.defaults.set(2, forKey: "SettingsSyncSyncedLayoutEdits")
                macA.defaults.set(Date(timeIntervalSinceReferenceDate: 651_000_000), forKey: "SettingsSyncPendingModified")
                let bookkeeping = ["SettingsSyncBaseSettingsDigest", "SettingsSyncBaseLayoutDigest", "SettingsSyncLayoutEdits", "SettingsSyncSyncedLayoutEdits", "SettingsSyncPendingModified", "SettingsSyncFolderBookmark", "SettingsSyncLastSynced"]
                let before = bookkeeping.map { macA.defaults.object(forKey: $0) as? NSObject }

                try TracerMac.with(name: "B", folder: folder, hardware: "HARDWARE-B", uid: 501) { macB in
                    macA.launch()
                    macA.settle()
                    // A joined or founded the group, with its own value, and wrote its own file.
                    #expect(macA.state.isEnabled)
                    #expect(macA.state.pendingJoin == nil)
                    #expect(macA.state.replica.live(.whole("ShowOnHover")).map(\.payload) == [.value(.bool(true))])
                    #expect(macA.defaults.string(forKey: "SettingsSyncLegacyDeviceID") == oldID)

                    // Mac B is fresh: Turn On… joins the folder, which holds A's file.
                    macB.launch()
                    macB.command(.turnOn(TracerMac.folderIdentity))
                    macB.settle()
                    #expect(macB.state.isEnabled)
                    #expect(macB.hint == .restart)
                    #expect(macB.defaults.object(forKey: "ShowOnHover") == nil)
                    macB.command(.restart)
                    macB.settle()
                    #expect(macB.relaunched)
                    #expect(macB.defaults.object(forKey: "ShowOnHover") as? Bool == true)
                    // Both Macs are quiet now.
                    macA.check()
                    macB.check()
                    #expect(macA.hint == nil)
                    #expect(macB.hint == nil)
                }

                // The folder holds the two device files and the legacy file, nothing else.
                let files = listing(of: folder)
                #expect(files.count == 5)
                #expect(files.filter { $0.hasPrefix("holzBar/Macs/") }.count == 2)
                #expect(files.contains("holzBar/Settings.plist"))
                #expect(files.filter { $0.hasPrefix("holzBar/Macs/") && $0.hasSuffix(".plist") }.count == 2)
                // The legacy file is as it was, and so is every key of the earlier builds on Mac A.
                #expect(try Data(contentsOf: legacy) == legacyBytes)
                #expect(try legacy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == legacyDate)
                #expect(bookkeeping.map { macA.defaults.object(forKey: $0) as? NSObject } == before)
                #expect(macA.defaults.object(forKey: "SettingsSyncLastSynced") as? Date == lastSynced)
            }
        }
    }
}

// MARK: - The Mac of the tracer

/// A Mac that does by hand what the app's host does: it feeds the events to `SyncEngine.handle` and carries
/// out the effects in order, on real files (the sync folder, the state file, a preferences suite).
final class TracerMac {
    static let folderIdentity: SyncFolderIdentity = "F1"

    let defaults: UserDefaults
    private let domain: String
    private let folder: URL
    private let hardware: String
    private let uid: UInt32
    private let store: SyncDefaultsStore
    private let stateStore: SyncStateStore
    private let table = SyncUnitTable.version1(normalizers: .canonical)
    private let fresh: SyncFreshIdentity
    private var tick: Double = 0
    private var timers: [SyncTimer] = []

    private(set) var state = SyncState(mac: SyncFixtures.macC, nonce: "none", isEnabled: false)
    private(set) var relaunched = false

    private init(name: String, folder: URL, hardware: String, uid: UInt32, support: URL, caches: URL) throws {
        domain = "holzBar.tests.Tracer.\(name).\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: domain))
        self.folder = folder
        self.hardware = hardware
        self.uid = uid
        store = SyncDefaultsStore(defaults: defaults, domainName: domain)
        stateStore = SyncStateStore(supportDirectory: support, cachesDirectory: caches)
        fresh = SyncFreshIdentity(mac: SyncMacID(UUID()), nonce: "nonce-\(name)")
    }

    static func with(name: String, folder: URL, hardware: String, uid: UInt32, _ body: (TracerMac) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "holzBar.tests.TracerMac.\(UUID().uuidString)", directoryHint: .isDirectory)
        let support = root.appending(path: "Support", directoryHint: .isDirectory)
        let caches = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let mac = try TracerMac(name: name, folder: folder, hardware: hardware, uid: uid, support: support, caches: caches)
        defer {
            mac.defaults.removePersistentDomain(forName: mac.domain)
            try? FileManager.default.removeItem(at: root)
        }
        try body(mac)
    }

    var hint: SyncHint? {
        SyncEngine.view(of: state, environment: environment()).hint
    }

    // MARK: Events

    func launch() {
        let input = SyncLaunchInput(
            snapshot: snapshot(),
            stored: stateStore.load().forEngine,
            identity: SyncIdentityInput(
                storedID: defaults.string(forKey: "SettingsSyncDeviceID"),
                storedHash: defaults.string(forKey: "SettingsSyncDeviceHash"),
                salt: defaults.data(forKey: "SettingsSyncDeviceSalt"),
                hardwareID: hardware,
                uid: uid
            ),
            defaultsGeneration: store.generation,
            lastSyncedSeen: store.lastSyncedSeen,
            syncIsOn: defaults.bool(forKey: "SyncsSettingsWithICloud"),
            folder: Self.folderIdentity
        )
        let step = SyncEngine.launch(input, environment: environment())
        state = step.state
        run(step.effects)
    }

    func command(_ command: SyncCommand) {
        feed(.defaultsChanged(snapshot()))
        feed(.command(command))
    }

    func check() {
        feed(.timer(.check))
        settle()
    }

    /// Fires the timers the engine scheduled, until none is left (the poll excepted, which reschedules itself).
    func settle() {
        for _ in 0..<50 {
            let due = timers.filter { $0 != .periodic }
            timers = timers.filter { $0 == .periodic }
            if due.isEmpty {
                return
            }
            for timer in due {
                feed(.timer(timer))
            }
        }
        Issue.record("the timers did not settle")
    }

    private func feed(_ event: SyncEvent) {
        let step = SyncEngine.handle(event, state: state, environment: environment())
        state = step.state
        run(step.effects)
    }

    // MARK: Effects

    private func run(_ effects: [SyncEffect]) {
        for effect in effects {
            switch effect {
            case .applyUnits(let units):
                store.apply(units, table: table)
            case .applyKnownApplications(let applications):
                store.applyKnownApplications(applications)
            case .persist(let persist):
                store.setGeneration(persist.generation)
                store.setCounterMirror(persist.counter)
                stateStore.raiseHighWater(to: persist.counter)
                store.flush()
                do {
                    try stateStore.persist(state)
                } catch {
                    Issue.record("the state was not persisted: \(error)")
                }
            case .readFolder(let request):
                let read = SyncFolderReader.read(request, syncFolder: folder, isDownloaded: { _ in true })
                feed(.folderRead(read, purpose: request.purpose))
            case .writeOwnFile(let request):
                feed(.writeFinished(SyncFolderWriter.write(request, syncFolder: folder)))
            case .schedule(let timer, _):
                timers.removeAll { $0 == timer }
                timers.append(timer)
            case .cancelTimer(let timer):
                timers.removeAll { $0 == timer }
            case .relaunch:
                relaunched = true
            case .requestDownload:
                break
            case .storeIdentity(let mac, let legacyID):
                let salt = defaults.data(forKey: "SettingsSyncDeviceSalt") ?? Data("tracer-salt".utf8)
                defaults.set(salt, forKey: "SettingsSyncDeviceSalt")
                defaults.set(mac.rawValue, forKey: "SettingsSyncDeviceID")
                defaults.set(SettingsSyncDevice.hardwareHash(of: hardware, uid: uid, salt: salt), forKey: "SettingsSyncDeviceHash")
                if let legacyID {
                    defaults.set(legacyID, forKey: "SettingsSyncLegacyDeviceID")
                }
            case .commitFolder:
                defaults.set(true, forKey: "SyncsSettingsWithICloud")
            case .forgetFolder:
                defaults.set(false, forKey: "SyncsSettingsWithICloud")
            }
        }
    }

    // MARK: Inputs

    private func snapshot() -> SyncSnapshot {
        store.snapshot(table: table, generation: .g27, baselineKeys: Set(state.baseline.keys))
    }

    private func environment() -> SyncEnvironment {
        tick += 1
        let now = Date(timeIntervalSince1970: 1_800_000_000 + tick)
        return SyncEnvironment(
            table: table,
            generation: .g27,
            now: now,
            unixSeconds: UInt64(now.timeIntervalSince1970),
            counterFloors: SyncCounterFloors(mirror: store.counterMirror, highWater: stateStore.highWater),
            guards: .all,
            freshIdentity: fresh
        )
    }
}
