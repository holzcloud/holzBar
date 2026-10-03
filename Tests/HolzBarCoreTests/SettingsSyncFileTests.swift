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

    private func newer(in file: [String: Any]) -> (settings: [String: Any], modified: Date)? {
        SettingsSyncFile.newerSettings(
            in: file,
            lastSynced: lastSynced,
            deviceID: thisMac,
            computerName: "Mac",
            localKeys: localKeys
        )
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
        let result = SettingsSyncFile.newerSettings(
            in: file(deviceID: otherMac, modified: .distantPast.addingTimeInterval(1), settings: [:]),
            lastSynced: nil,
            deviceID: thisMac,
            computerName: nil,
            localKeys: localKeys
        )
        #expect(result != nil)
    }

    @Test("A file dated far in the future is ignored")
    func farFutureFileIgnored() {
        let now = lastSynced.addingTimeInterval(3600)
        func newer(modified: Date) -> (settings: [String: Any], modified: Date)? {
            SettingsSyncFile.newerSettings(
                in: file(deviceID: otherMac, modified: modified, settings: ["UseIceBar": true]),
                lastSynced: lastSynced,
                deviceID: thisMac,
                computerName: nil,
                localKeys: localKeys,
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
