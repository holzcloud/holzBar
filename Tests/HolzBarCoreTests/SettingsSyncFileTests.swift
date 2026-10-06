import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSyncFile")
struct SettingsSyncFileTests {
    private let thisMac = "THIS-MAC"
    private let otherMac = "OTHER-MAC"
    private let lastSynced = Date(timeIntervalSince1970: 1_000_000)
    private let localKeys: Set<String> = ["SyncsSettingsWithICloud", "SettingsSyncLastSynced"]

    private func file(deviceID: String, modified: Date?, settings: [String: Any]?) -> [String: Any] {
        var file: [String: Any] = [SettingsSyncDevice.deviceIDKey: deviceID]
        if let modified {
            file[SettingsSyncFile.modifiedKey] = modified
        }
        if let settings {
            file[SettingsSyncFile.settingsKey] = settings
        }
        return file
    }

    /// The file's contents, if another Mac wrote them after this Mac last synced.
    private func newer(
        in file: [String: Any],
        lastSynced: Date?? = nil,
        computerName: String? = "Mac",
        now: Date = .now
    ) -> SettingsSyncFile.Contents? {
        SettingsSyncFile.contents(
            of: file,
            lastSynced: lastSynced ?? self.lastSynced,
            deviceID: thisMac,
            computerName: computerName,
            localKeys: localKeys,
            now: now
        ).flatMap { $0.isNewer ? $0 : nil }
    }

    @Test("A newer file from another Mac is applied")
    func newerFileFromAnotherMac() throws {
        let modified = lastSynced.addingTimeInterval(60)
        let result = try #require(newer(in: file(deviceID: otherMac, modified: modified, settings: ["UseIceBar": true])))
        #expect(result.modified == modified)
        #expect(result.settings["UseIceBar"] as? Bool == true)
    }

    @Test("This Mac's own file is ignored")
    func ownFileIgnored() {
        let modified = lastSynced.addingTimeInterval(60)
        #expect(newer(in: file(deviceID: thisMac, modified: modified, settings: ["UseIceBar": true])) == nil)
    }

    @Test("An older file is ignored")
    func olderFileIgnored() {
        #expect(newer(in: file(deviceID: otherMac, modified: lastSynced, settings: ["UseIceBar": true])) == nil)
        let older = lastSynced.addingTimeInterval(-60)
        #expect(newer(in: file(deviceID: otherMac, modified: older, settings: ["UseIceBar": true])) == nil)
    }

    @Test("Local keys are not synced")
    func localKeysNotSynced() throws {
        let settings: [String: Any] = [
            "SyncsSettingsWithICloud": false,
            "SettingsSyncLastSynced": Date.now,
            "UseIceBar": true,
        ]
        let modified = lastSynced.addingTimeInterval(60)
        let result = try #require(newer(in: file(deviceID: otherMac, modified: modified, settings: settings)))
        #expect(Set(result.settings.keys) == ["UseIceBar"])
    }

    @Test("A file without settings or date is ignored")
    func fileWithoutSettingsOrDate() {
        let modified = lastSynced.addingTimeInterval(60)
        #expect(newer(in: file(deviceID: otherMac, modified: modified, settings: nil)) == nil)
        #expect(newer(in: file(deviceID: otherMac, modified: nil, settings: ["UseIceBar": true])) == nil)
    }

    @Test("A Mac that never synced applies any file from another Mac")
    func neverSynced() {
        let result = newer(
            in: file(deviceID: otherMac, modified: .distantPast.addingTimeInterval(1), settings: [:]),
            lastSynced: .some(nil),
            computerName: nil
        )
        #expect(result != nil)
    }

    @Test("A file dated far in the future is ignored")
    func farFutureFileIgnored() {
        let now = lastSynced.addingTimeInterval(3600)
        func newer(modified: Date) -> SettingsSyncFile.Contents? {
            self.newer(
                in: file(deviceID: otherMac, modified: modified, settings: ["UseIceBar": true]),
                computerName: nil,
                now: now
            )
        }
        // Another Mac's clock may run a little ahead.
        #expect(newer(modified: now.addingTimeInterval(60)) != nil)
        #expect(newer(modified: now.addingTimeInterval(SettingsSyncFile.allowedClockSkew)) != nil)
        // A file dated years ahead would make this Mac ignore every later change.
        #expect(newer(modified: now.addingTimeInterval(SettingsSyncFile.allowedClockSkew + 1)) == nil)
        #expect(newer(modified: .distantFuture) == nil)
    }

    private func contents(in file: [String: Any], now: Date = .now) -> SettingsSyncFile.Contents? {
        SettingsSyncFile.contents(
            of: file,
            lastSynced: lastSynced,
            deviceID: thisMac,
            computerName: nil,
            localKeys: localKeys,
            now: now
        )
    }

    @Test("The contents tell this Mac's, older and newer files apart")
    func contentsOfFile() throws {
        let modified = lastSynced.addingTimeInterval(60)
        let now = lastSynced.addingTimeInterval(120)
        let own = try #require(contents(in: file(deviceID: thisMac, modified: modified, settings: ["UseIceBar": true]), now: now))
        #expect(own.isFromThisMac)
        #expect(!own.isNewer)
        let other = try #require(contents(in: file(deviceID: otherMac, modified: modified, settings: ["UseIceBar": true]), now: now))
        #expect(!other.isFromThisMac)
        #expect(other.isNewer)
        #expect(other.modified == modified)
        let older = try #require(contents(in: file(deviceID: otherMac, modified: lastSynced, settings: [:]), now: now))
        #expect(!older.isNewer)
        let future = now.addingTimeInterval(SettingsSyncFile.allowedClockSkew + 1)
        let farAhead = try #require(contents(in: file(deviceID: otherMac, modified: future, settings: [:]), now: now))
        #expect(!farAhead.isFromThisMac)
        #expect(!farAhead.isNewer)
    }

    @Test("The contents leave out the local keys")
    func contentsWithoutLocalKeys() throws {
        let settings: [String: Any] = ["SyncsSettingsWithICloud": true, "UseIceBar": true]
        let result = try #require(contents(in: file(deviceID: otherMac, modified: lastSynced, settings: settings)))
        #expect(Set(result.settings.keys) == ["UseIceBar"])
    }

    @Test("The contents list the file's current layouts")
    func contentsCurrentLayouts() throws {
        var listed = file(deviceID: otherMac, modified: lastSynced, settings: [:])
        listed[SettingsSyncFile.currentLayoutsKey] = ["ItemSections", "MacOS27Layout"]
        #expect(try #require(contents(in: listed)).currentLayouts == ["ItemSections", "MacOS27Layout"])
        // Files of earlier builds list none.
        let earlier = file(deviceID: otherMac, modified: lastSynced, settings: [:])
        #expect(try #require(contents(in: earlier)).currentLayouts.isEmpty)
        var wrongType = earlier
        wrongType[SettingsSyncFile.currentLayoutsKey] = "ItemSections"
        #expect(try #require(contents(in: wrongType)).currentLayouts.isEmpty)
        var copied = listed
        copied[SettingsSyncFile.copiedLayoutsKey] = ["ItemSections"]
        #expect(try #require(contents(in: copied)).copiedLayouts == ["ItemSections"])
        #expect(try #require(contents(in: listed)).copiedLayouts.isEmpty)
    }

    @Test("The contents give the writes a version holds, this Mac's apart, which files of earlier builds lack")
    func contentsSeen() throws {
        #expect(SettingsSyncFile.seenKey == "seen")
        let thisWrite = lastSynced.addingTimeInterval(-60)
        var recorded = file(deviceID: otherMac, modified: lastSynced, settings: [:])
        recorded[SettingsSyncFile.seenKey] = [thisMac: thisWrite, otherMac: lastSynced, "third": "not a date"]
        let read = try #require(contents(in: recorded))
        #expect(read.seen == [otherMac: lastSynced])
        #expect(read.seenWrite == thisWrite)
        // A record without this Mac holds none of its writes; files of earlier builds, or a
        // record of the wrong type, record none.
        recorded[SettingsSyncFile.seenKey] = [otherMac: lastSynced]
        #expect(try #require(contents(in: recorded)).seen == [otherMac: lastSynced])
        #expect(try #require(contents(in: recorded)).seenWrite == nil)
        let earlier = file(deviceID: otherMac, modified: lastSynced, settings: [:])
        #expect(try #require(contents(in: earlier)).seen == nil)
        #expect(try #require(contents(in: earlier)).seenWrite == nil)
        recorded[SettingsSyncFile.seenKey] = [lastSynced]
        #expect(try #require(contents(in: recorded)).seen == nil)
        // The record survives a round trip through the file as written, in whole seconds.
        let written = SettingsSyncFile.seenToWrite([thisMac: thisWrite], deviceID: otherMac, modified: lastSynced.addingTimeInterval(0.4))
        recorded[SettingsSyncFile.seenKey] = written
        let data = try PropertyListSerialization.data(fromPropertyList: recorded, format: .xml, options: 0)
        let roundTrip = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let readBack = try #require(contents(in: roundTrip))
        #expect(readBack.seenWrite.map(SettingsSyncPolicy.wholeSeconds) == SettingsSyncPolicy.wholeSeconds(thisWrite))
        #expect(readBack.seen?[otherMac].map(SettingsSyncPolicy.wholeSeconds) == SettingsSyncPolicy.wholeSeconds(lastSynced))
    }

    @Test("The record of writes holds the writing Mac's write and at most the newest writes of the limit")
    func seenRecordLimit() {
        #expect(SettingsSyncFile.seenLimit == 64)
        let written = SettingsSyncFile.seenToWrite(["a": lastSynced], deviceID: thisMac, modified: lastSynced.addingTimeInterval(60))
        #expect(written == ["a": lastSynced, thisMac: lastSynced.addingTimeInterval(60)])
        // This Mac's own entry is replaced by its write.
        #expect(SettingsSyncFile.seenToWrite([thisMac: lastSynced], deviceID: thisMac, modified: lastSynced.addingTimeInterval(60)) == [thisMac: lastSynced.addingTimeInterval(60)])
        // Of too many writes, the newest are kept, and the writing Mac's always.
        var many = [String: Date]()
        for index in 0 ..< 100 {
            many["mac\(index)"] = lastSynced.addingTimeInterval(Double(index))
        }
        let limited = SettingsSyncFile.limitedSeen(many)
        #expect(limited.count == 64)
        #expect(limited["mac99"] != nil)
        #expect(limited["mac36"] != nil)
        #expect(limited["mac35"] == nil)
        #expect(SettingsSyncFile.limitedSeen(["a": lastSynced]) == ["a": lastSynced])
        let full = SettingsSyncFile.seenToWrite(many, deviceID: thisMac, modified: lastSynced.addingTimeInterval(-1))
        #expect(full.count == 64)
        #expect(full[thisMac] == lastSynced.addingTimeInterval(-1))
        #expect(full["mac36"] == nil)
        var tooMany = file(deviceID: otherMac, modified: lastSynced, settings: [:])
        tooMany[SettingsSyncFile.seenKey] = many
        #expect(contents(in: tooMany)?.seen?.count == 64)
    }

    @Test("A file without date or settings has no contents")
    func contentsWithoutDateOrSettings() {
        #expect(contents(in: file(deviceID: otherMac, modified: lastSynced, settings: nil)) == nil)
        #expect(contents(in: file(deviceID: otherMac, modified: nil, settings: [:])) == nil)
    }

    @Test("Online-only files are not read at launch")
    func localFiles() {
        let dataless = UInt32(SF_DATALESS)
        #expect(!SettingsSyncFile.isLocal(flags: dataless, isUbiquitous: nil, downloadingStatus: nil))
        #expect(!SettingsSyncFile.isLocal(flags: dataless, isUbiquitous: false, downloadingStatus: nil))
        #expect(!SettingsSyncFile.isLocal(flags: 0, isUbiquitous: true, downloadingStatus: .notDownloaded))
        #expect(!SettingsSyncFile.isLocal(flags: 0, isUbiquitous: true, downloadingStatus: .downloaded))
        #expect(!SettingsSyncFile.isLocal(flags: 0, isUbiquitous: true, downloadingStatus: nil))
        #expect(SettingsSyncFile.isLocal(flags: 0, isUbiquitous: true, downloadingStatus: .current))
        #expect(SettingsSyncFile.isLocal(flags: 0, isUbiquitous: false, downloadingStatus: nil))
        #expect(SettingsSyncFile.isLocal(flags: 0, isUbiquitous: nil, downloadingStatus: nil))
    }

    // MARK: Reading

    /// A new, empty folder for one test.
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SettingsSyncFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test("A regular file is read")
    func regularFileIsRead() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Settings.plist")
        try Data("settings".utf8).write(to: url)
        #expect(SettingsSyncFile.readContents(atPath: url.path(percentEncoded: false)) == .contents(Data("settings".utf8)))
    }

    @Test("A missing file is missing")
    func missingFile() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Settings.plist").path(percentEncoded: false)
        #expect(SettingsSyncFile.readContents(atPath: path) == .missing)
    }

    @Test("A symbolic link is not followed")
    func symbolicLinkIsNotFollowed() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Elsewhere.plist")
        try Data("secret".utf8).write(to: target)
        let link = folder.appending(path: "Settings.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(SettingsSyncFile.readContents(atPath: link.path(percentEncoded: false)) == .refused(.notRegularFile))
    }

    @Test("A folder is not read")
    func folderIsNotRead() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(SettingsSyncFile.readContents(atPath: folder.path(percentEncoded: false)) == .refused(.notRegularFile))
    }

    @Test("A file over the limit is not read")
    func largeFileIsNotRead() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Settings.plist")
        try Data(count: 101).write(to: url)
        let path = url.path(percentEncoded: false)
        #expect(SettingsSyncFile.readContents(atPath: path, maximumSize: 100) == .refused(.tooLarge))
        #expect(SettingsSyncFile.readContents(atPath: path, maximumSize: 101) == .contents(Data(count: 101)))
    }

    @Test("holzBar writes no file larger than it reads")
    func sizeLimit() {
        #expect(SettingsSyncFile.fitsSizeLimit(byteCount: 0))
        #expect(SettingsSyncFile.fitsSizeLimit(byteCount: SettingsSyncFile.maximumFileSize))
        #expect(!SettingsSyncFile.fitsSizeLimit(byteCount: SettingsSyncFile.maximumFileSize + 1))
    }

    @Test("A file over the limit is never written over, and nothing of it is applied")
    func tooLargeFileIsLeftAlone() {
        #expect(SettingsSyncPolicy.File(refusal: .tooLarge) == .unreadable)
        #expect(SettingsSyncPolicy.File(refusal: .unreadable) == .unreadable)
        #expect(SettingsSyncPolicy.File(refusal: .notRegularFile) == .unusable)
        let file = SettingsSyncPolicy.File(refusal: .tooLarge)
        let sides = [
            SettingsSyncPolicy.Local(userDigest: "changed", base: "base", pending: nil, postponed: nil, forcesWrite: false),
            SettingsSyncPolicy.Local(userDigest: "base", base: nil, pending: nil, postponed: nil, forcesWrite: false),
            SettingsSyncPolicy.Local(userDigest: "base", base: "base", pending: nil, postponed: nil, forcesWrite: true),
        ]
        for local in sides {
            for trigger in [SettingsSyncPolicy.Trigger.localChange, .check, .launch] {
                #expect(SettingsSyncPolicy.decide(trigger, local: local, file: file) == .retry)
            }
        }
    }

    @Test("Only a real folder, or none yet, is written into")
    func usableFolder() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(SettingsSyncFile.isUsableFolder(atPath: folder.path(percentEncoded: false)))
        let missing = folder.appending(path: "holzBar")
        #expect(SettingsSyncFile.isUsableFolder(atPath: missing.path(percentEncoded: false)))
        let elsewhere = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let link = folder.appending(path: "linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        #expect(!SettingsSyncFile.isUsableFolder(atPath: link.path(percentEncoded: false)))
        let file = folder.appending(path: "file")
        try Data().write(to: file)
        #expect(!SettingsSyncFile.isUsableFolder(atPath: file.path(percentEncoded: false)))
    }
}
