import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSyncFile")
struct SettingsSyncFileTests {
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
