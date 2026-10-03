import Testing
@testable import HolzBarCore

@Suite("SettingsSyncLocation")
struct SettingsSyncLocationTests {
    private let iCloud = "/Users/anna/Library/Mobile Documents/com~apple~CloudDocs"

    @Test("Without a chosen folder, iCloud Drive is used and stored")
    func iCloudDriveWithoutAChoice() {
        let decision = SettingsSyncLocation.decide(resolution: .none, iCloudDrivePath: iCloud)
        #expect(decision.folderPath == iCloud)
        #expect(decision.storesBookmark)
        let withoutICloud = SettingsSyncLocation.decide(resolution: .none, iCloudDrivePath: nil)
        #expect(withoutICloud.folderPath == nil)
        #expect(!withoutICloud.storesBookmark)
    }

    @Test("A chosen folder wins, and a stale bookmark is stored again")
    func chosenFolderWins() {
        let fresh = SettingsSyncLocation.decide(resolution: .resolved(path: "/Users/anna/Nextcloud", isStale: false), iCloudDrivePath: iCloud)
        #expect(fresh.folderPath == "/Users/anna/Nextcloud")
        #expect(!fresh.storesBookmark)
        let stale = SettingsSyncLocation.decide(resolution: .resolved(path: "/Users/anna/Dropbox", isStale: true), iCloudDrivePath: iCloud)
        #expect(stale.folderPath == "/Users/anna/Dropbox")
        #expect(stale.storesBookmark)
    }

    @Test("A folder that cannot be found is not replaced by iCloud Drive")
    func missingFolderIsNotReplaced() {
        let decision = SettingsSyncLocation.decide(resolution: .failed, iCloudDrivePath: iCloud)
        #expect(decision.folderPath == nil)
        #expect(!decision.storesBookmark)
    }

    @Test("The sync file is holzBar/Settings.plist in the folder")
    func syncFilePath() {
        #expect(SettingsSyncLocation.syncFilePath(inFolder: "/Volumes/Share/Sync") == "/Volumes/Share/Sync/holzBar/Settings.plist")
        #expect(SettingsSyncLocation.syncFilePath(inFolder: "/Volumes/Share/Sync/") == "/Volumes/Share/Sync/holzBar/Settings.plist")
    }

    @Test("Folders are named for people")
    func displayNames() {
        let home = "/Users/anna"
        #expect(SettingsSyncLocation.displayName(forFolder: iCloud + "/", homePath: home, iCloudDrivePath: iCloud) == "iCloud Drive")
        #expect(SettingsSyncLocation.displayName(forFolder: "/Users/anna/Nextcloud", homePath: home, iCloudDrivePath: iCloud) == "~/Nextcloud")
        #expect(SettingsSyncLocation.displayName(forFolder: "/Users/annabel", homePath: home, iCloudDrivePath: nil) == "/Users/annabel")
        #expect(SettingsSyncLocation.displayName(forFolder: "/Volumes/Share", homePath: home, iCloudDrivePath: nil) == "/Volumes/Share")
    }
}
