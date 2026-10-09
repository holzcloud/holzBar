import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSyncDevice")
struct SettingsSyncDeviceTests {
    private let thisMac = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
    private let otherMac = "7C9E6679-7425-40DE-944B-E07FC1F90AE7"

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
