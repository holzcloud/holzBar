import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSyncDevice")
struct SettingsSyncDeviceTests {
    private let thisMac = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    private let otherMac = "7C9E6679-7425-40DE-944B-E07FC1F90AE7"

    @Test("A file with this Mac's id is from this Mac")
    func fileWithThisMacsID() {
        let file: [String: Any] = ["deviceID": thisMac, "device": "Someone else's Mac"]
        #expect(SettingsSyncDevice.isFromThisMac(file: file, deviceID: thisMac, computerName: "Studio"))
        #expect(SettingsSyncDevice.isFromThisMac(file: file, deviceID: thisMac, computerName: nil))
    }

    @Test("Two Macs with the same name are told apart")
    func sameNameDifferentID() {
        let file: [String: Any] = ["deviceID": otherMac, "device": "MacBook Pro"]
        #expect(!SettingsSyncDevice.isFromThisMac(file: file, deviceID: thisMac, computerName: "MacBook Pro"))
    }

    @Test("A name-only file from an older holzBar is recognised by name")
    func nameOnlyFile() {
        let file: [String: Any] = ["device": "MacBook Pro"]
        #expect(SettingsSyncDevice.isFromThisMac(file: file, deviceID: thisMac, computerName: "MacBook Pro"))
        #expect(!SettingsSyncDevice.isFromThisMac(file: file, deviceID: thisMac, computerName: "iMac"))
    }

    @Test("Without a computer name a name-only file is from another Mac")
    func nameOnlyFileWithoutComputerName() {
        let named: [String: Any] = ["device": "MacBook Pro"]
        let unnamed: [String: Any] = ["device": ""]
        #expect(!SettingsSyncDevice.isFromThisMac(file: named, deviceID: thisMac, computerName: nil))
        #expect(!SettingsSyncDevice.isFromThisMac(file: unnamed, deviceID: thisMac, computerName: nil))
        #expect(!SettingsSyncDevice.isFromThisMac(file: unnamed, deviceID: thisMac, computerName: ""))
    }
}
