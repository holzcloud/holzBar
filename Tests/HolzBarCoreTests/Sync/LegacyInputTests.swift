//
//  LegacyInputTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncLegacyInput")
struct LegacyInputTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func file(modified: Date? = nil, deviceID: String? = "OLD-MAC", device: String? = nil, settings: [String: Any]? = ["ShowOnHover": true]) throws -> Data {
        var fields: [String: Any] = [:]
        fields[SettingsSyncFile.modifiedKey] = modified ?? date
        fields[SettingsSyncDevice.deviceIDKey] = deviceID
        fields[SettingsSyncDevice.deviceNameKey] = device
        fields[SettingsSyncFile.settingsKey] = settings
        return try PropertyListSerialization.data(fromPropertyList: fields, format: .xml, options: 0)
    }

    private func read(_ data: Data) throws -> SyncLegacyFile {
        try SyncLegacyInput.read(data).get()
    }

    @Test("A file of 1 MiB plus one byte is refused")
    func tooLarge() throws {
        let limit = SettingsSyncFile.maximumFileSize
        let padded = try PropertyListSerialization.data(
            fromPropertyList: [SettingsSyncFile.settingsKey: [String: Any](), "pad": Data(count: limit)],
            format: .binary,
            options: 0
        )
        #expect(SyncLegacyInput.read(padded) == .failure(.tooLarge(padded.count)))
        #expect(SyncLegacyInput.read(Data(count: limit + 1)) == .failure(.tooLarge(limit + 1)))
    }

    @Test("A beta 1 file returns its date, writer and settings")
    func betaFile() throws {
        let legacy = try read(file(settings: ["ShowOnHover": true, "Count": 3, "Name": "x"]))
        #expect(legacy.modified == date)
        #expect(legacy.deviceID == "OLD-MAC")
        #expect(legacy.settings == ["ShowOnHover": .bool(true), "Count": .integer(3), "Name": .string("x")])
    }

    @Test("A file of the earliest builds, with only a computer name, has no writer ID")
    func earliestFile() throws {
        let legacy = try read(file(deviceID: nil, device: "Christophs MacBook"))
        #expect(legacy.deviceID == nil)
        #expect(!legacy.isWritten(byLegacyDeviceID: "OLD-MAC"))
        #expect(!legacy.isWritten(byLegacyDeviceID: nil))
    }

    @Test("Settings that do not convert are dropped and the file is still accepted")
    func unconvertibleSettings() throws {
        let legacy = try read(file(settings: ["Good": 1, "Bad": Double.nan]))
        #expect(legacy.settings == ["Good": .integer(1)])
    }

    @Test("Files with the same date and writer have the same identity whatever the settings")
    func identityDigest() throws {
        let first = try read(file(settings: ["A": 1]))
        let second = try read(file(settings: ["B": 2, "C": 3]))
        #expect(first.identityDigest == second.identityDigest)
        #expect(first.identityDigest != (try read(file(modified: date.addingTimeInterval(1)))).identityDigest)
        #expect(first.identityDigest != (try read(file(deviceID: "OTHER-MAC"))).identityDigest)
    }

    @Test("The writer's sync ID is recognized")
    func writtenByLegacyID() throws {
        let legacy = try read(file())
        #expect(legacy.isWritten(byLegacyDeviceID: "OLD-MAC"))
        #expect(!legacy.isWritten(byLegacyDeviceID: "NEW-MAC"))
        #expect(!legacy.isWritten(byLegacyDeviceID: nil))
    }

    @Test("Damaged files are refused")
    func damaged() throws {
        #expect(SyncLegacyInput.read(Data([0xFF, 0x00, 0xFE, 0x01, 0x80, 0x99, 0x00, 0x00])) == .failure(.notPropertyList))
        let array = try PropertyListSerialization.data(fromPropertyList: [1], format: .xml, options: 0)
        #expect(SyncLegacyInput.read(array) == .failure(.wrongStructure("root")))
        #expect(SyncLegacyInput.read(try file(settings: nil)) == .failure(.wrongStructure("settings")))
    }
}
