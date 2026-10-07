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

    @Test("The same Mac keeps its identity")
    func sameMac() {
        let salt = SettingsSyncDevice.makeSalt()
        let hash = SettingsSyncDevice.hardwareHash(of: "A", salt: salt)
        #expect(SettingsSyncDevice.identity(storedHash: hash, salt: salt, hardwareID: "A") == .same)
    }

    @Test("Defaults copied from another Mac are recognised")
    func copiedDefaults() {
        let salt = SettingsSyncDevice.makeSalt()
        let hash = SettingsSyncDevice.hardwareHash(of: "A", salt: salt)
        #expect(SettingsSyncDevice.identity(storedHash: hash, salt: salt, hardwareID: "B") == .otherMac)
    }

    @Test("Without a stored hash the Mac is seen for the first time")
    func firstSeen() {
        let salt = SettingsSyncDevice.makeSalt()
        #expect(SettingsSyncDevice.identity(storedHash: nil, salt: nil, hardwareID: "A") == .firstSeen)
        #expect(SettingsSyncDevice.identity(storedHash: nil, salt: salt, hardwareID: "A") == .firstSeen)
        #expect(SettingsSyncDevice.identity(storedHash: "hash", salt: nil, hardwareID: "A") == .firstSeen)
    }

    @Test("Without a hardware id nothing is decided")
    func unknownHardware() {
        let salt = SettingsSyncDevice.makeSalt()
        #expect(SettingsSyncDevice.identity(storedHash: "hash", salt: salt, hardwareID: nil) == .unknown)
        #expect(SettingsSyncDevice.identity(storedHash: nil, salt: nil, hardwareID: nil) == .unknown)
    }

    @Test("The hardware hash is salted hexadecimal")
    func hardwareHashFormat() {
        let salt = Data(repeating: 1, count: 32)
        let hash = SettingsSyncDevice.hardwareHash(of: thisMac, salt: salt)
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(hash == SettingsSyncDevice.hardwareHash(of: thisMac, salt: salt))
        #expect(hash != SettingsSyncDevice.hardwareHash(of: thisMac, salt: Data(repeating: 2, count: 32)))
        #expect(hash != SettingsSyncDevice.hardwareHash(of: otherMac, salt: salt))
    }

    @Test("The hash with the user ID is salted hexadecimal and differs per user")
    func hardwareHashWithUser() {
        let salt = Data(repeating: 1, count: 32)
        let hash = SettingsSyncDevice.hardwareHash(of: thisMac, uid: 501, salt: salt)
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(hash == SettingsSyncDevice.hardwareHash(of: thisMac, uid: 501, salt: salt))
        #expect(hash != SettingsSyncDevice.hardwareHash(of: thisMac, uid: 502, salt: salt))
        #expect(hash != SettingsSyncDevice.hardwareHash(of: thisMac, salt: salt))
        #expect(!hash.contains(thisMac.lowercased()))
    }

    @Test("A copied account on the same Mac is another identity; the old hash does not match")
    func identityWithUser() {
        let salt = SettingsSyncDevice.makeSalt()
        let hash = SettingsSyncDevice.hardwareHash(of: "A", uid: 501, salt: salt)
        #expect(SettingsSyncDevice.identity(storedHash: hash, salt: salt, hardwareID: "A", uid: 501) == .same)
        #expect(SettingsSyncDevice.identity(storedHash: hash, salt: salt, hardwareID: "A", uid: 502) == .otherMac)
        #expect(SettingsSyncDevice.identity(storedHash: hash, salt: salt, hardwareID: "B", uid: 501) == .otherMac)
        let old = SettingsSyncDevice.hardwareHash(of: "A", salt: salt)
        #expect(SettingsSyncDevice.identity(storedHash: old, salt: salt, hardwareID: "A", uid: 501) == .otherMac)
        #expect(SettingsSyncDevice.identity(storedHash: nil, salt: nil, hardwareID: "A", uid: 501) == .firstSeen)
        #expect(SettingsSyncDevice.identity(storedHash: hash, salt: salt, hardwareID: nil, uid: 501) == .unknown)
    }

    @Test("Salts are 32 random bytes")
    func salts() {
        let first = SettingsSyncDevice.makeSalt()
        let second = SettingsSyncDevice.makeSalt()
        #expect(first.count == 32)
        #expect(first != second)
    }
}
