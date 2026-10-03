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
}
