//
//  DeviceFileCodecTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncDeviceFile")
struct DeviceFileCodecTests {
    private let macA = DeviceFileCodecTests.mac("A")
    private let macB = DeviceFileCodecTests.mac("B")
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static func mac(_ digit: Character) -> SyncMacID {
        func block(_ count: Int) -> String {
            String(repeating: digit, count: count)
        }
        guard let id = SyncMacID("\(block(8))-\(block(4))-\(block(4))-\(block(4))-\(block(12))") else {
            preconditionFailure("The test identity is malformed")
        }
        return id
    }

    private func entry(_ mac: SyncMacID, _ n: Int64, value: Any? = true, deleted: Bool? = nil) -> [String: Any] {
        var fields: [String: Any] = ["mac": mac.rawValue, "n": n, "at": date]
        if let value {
            fields["value"] = value
        }
        if let deleted {
            fields["deleted"] = deleted
        }
        return fields
    }

    /// A valid device file of Mac A, with `overrides` applied to its top-level fields.
    private func file(_ overrides: [String: Any?] = [:]) -> [String: Any] {
        var fields: [String: Any] = [
            "format": 1,
            "minor": 0,
            "unitTable": 1,
            "mac": macA.rawValue,
            "installation": "nonce",
            "written": date,
            "context": [macA.rawValue: 5],
            "units": ["ShowOnHover": [entry(macA, 5)]],
            "entries": [String: Any](),
            "sets": [String: Any](),
        ]
        for (key, value) in overrides {
            fields[key] = value
        }
        return fields
    }

    private func bytes(_ fields: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: fields, format: .binary, options: 0)
    }

    private func decode(_ fields: [String: Any], name: String? = nil) throws -> Result<SyncDeviceFile.Contents, SyncRefusal> {
        SyncDeviceFile.decode(try bytes(fields), fileName: name ?? "\(macA.rawValue).plist")
    }

    private func refusal(_ fields: [String: Any], name: String? = nil) throws -> SyncRefusal? {
        if case .failure(let refusal) = try decode(fields, name: name) {
            return refusal
        }
        return nil
    }

    // MARK: Limits

    @Test("A file of exactly 1 MiB is parsed and one byte more is refused")
    func readLimit() throws {
        func padded(_ count: Int) throws -> Data {
            try bytes(file(["pad": Data(count: count)]))
        }
        let limit = SyncDeviceFile.maximumReadSize
        let first = try padded(1_000_000)
        let exact = try padded(1_000_000 + limit - first.count)
        #expect(exact.count == limit)
        let name = "\(macA.rawValue).plist"
        #expect(throws: Never.self) { try SyncDeviceFile.decode(exact, fileName: name).get() }
        #expect(SyncDeviceFile.decode(exact + Data([0]), fileName: name) == .failure(.tooLarge(limit + 1)))
    }

    @Test("The writer's limit equals the reader's")
    func writerLimitEqualsReaderLimit() {
        #expect(SyncDeviceFile.maximumWriteSize == SyncDeviceFile.maximumReadSize)
    }

    @Test("A replica that does not fit in 1 MiB is not encoded")
    func writeLimit() {
        let entry = SyncEntry(dot: SyncDot(mac: macA, n: 1), at: date, payload: .value(.data(Data(count: 2 << 20))))
        let replica = SyncReplica(
            context: SyncContext(counters: [macA: 1]),
            registers: [.whole("Big"): [entry]]
        )
        let contents = SyncDeviceFile.Contents(unitTable: 1, mac: macA, installation: "n", written: date, replica: replica)
        do {
            _ = try SyncDeviceFile.encode(contents)
            Issue.record("An oversize file was encoded")
        } catch {
            guard case .tooLarge = error else {
                Issue.record("Expected tooLarge, got \(error)")
                return
            }
        }
    }

    // MARK: Refusals

    @Test("Bytes that are not a property list are refused")
    func notPropertyList() throws {
        let name = "\(macA.rawValue).plist"
        #expect(SyncDeviceFile.decode(Data([0xFF, 0x00, 0xFE, 0x01, 0x80, 0x99, 0x00, 0x00]), fileName: name) == .failure(.notPropertyList))
        let valid = try bytes(file())
        #expect(SyncDeviceFile.decode(valid.dropLast(12), fileName: name) == .failure(.notPropertyList))
        #expect(SyncDeviceFile.decode(Data(), fileName: name) == .failure(.notPropertyList))
    }

    @Test("A property list that is not a dictionary is refused")
    func topLevelArray() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [1, 2, 3], format: .binary, options: 0)
        #expect(SyncDeviceFile.decode(data, fileName: "\(macA.rawValue).plist") == .failure(.wrongStructure("root")))
    }

    @Test("A newer major format is refused and named")
    func newerFormat() throws {
        #expect(try refusal(file(["format": 2])) == .newerFormat(2))
        // Even when the rest of the file this build cannot read is garbage.
        #expect(try refusal(["format": 7, "mac": 1]) == .newerFormat(7))
    }

    @Test("A newer minor format is read and its unknown fields pass through")
    func newerMinor() throws {
        let contents = try decode(file(["minor": 5, "future": "x"])).get()
        #expect(contents.minor == 5)
        #expect(contents.extra == ["future": .string("x")])
    }

    @Test("A file named for a different Mac is refused")
    func nameMismatch() throws {
        #expect(try refusal(file(), name: "\(macB.rawValue).plist") == .nameMismatch)
        #expect(try refusal(file(), name: "Settings.plist") == .nameMismatch)
        #expect(try refusal(file(), name: "\(macA.rawValue.lowercased()).plist") == .nameMismatch)
    }

    @Test("A counter beyond the limit is refused in a context and in an entry")
    func counterRange() throws {
        let tooBig = Int64(SyncDeviceFile.maximumCounter) + 1
        #expect(try refusal(file(["context": [macA.rawValue: tooBig]])) == .counterOutOfRange)
        #expect(try refusal(file(["context": [macA.rawValue: 5], "units": ["U": [entry(macA, tooBig)]]])) == .counterOutOfRange)
        #expect(try refusal(file(["context": [macA.rawValue: 5], "units": ["U": [entry(macA, 0)]]])) == .counterOutOfRange)
        #expect(try refusal(file(["context": [macA.rawValue: -1]])) == .counterOutOfRange)
        let limit = Int64(SyncDeviceFile.maximumCounter)
        #expect(try refusal(file(["context": [macA.rawValue: limit], "units": ["U": [entry(macA, limit)]]])) == nil)
    }

    @Test("A family with more than 1,024 items is refused")
    func familyLimit() throws {
        func family(_ count: Int) -> [String: Any] {
            var items: [String: Any] = [:]
            for index in 0..<count {
                items["item\(index)"] = [entry(macA, 5)]
            }
            return ["Hotkeys": items]
        }
        #expect(try refusal(file(["entries": family(SyncDeviceFile.maximumEntriesPerFamily + 1)])) == .tooManyEntries("Hotkeys"))
        #expect(try refusal(file(["entries": family(SyncDeviceFile.maximumEntriesPerFamily)])) == nil)
    }

    @Test("A set with more than 2,000 elements is refused")
    func setLimit() throws {
        let tooMany = (0...SyncDeviceFile.maximumSetElements).map { "element\($0)" }
        #expect(try refusal(file(["sets": ["Seen": tooMany]])) == .tooManyEntries("Seen"))
    }

    @Test("An entry the file's own context has not seen is refused")
    func uncoveredEntry() throws {
        #expect(try refusal(file(["context": [macA.rawValue: 3]])) == .uncoveredEntry)
        #expect(try refusal(file(["context": [String: Any]()])) == .uncoveredEntry)
    }

    @Test("An entry with both a value and a deletion, or neither, is refused")
    func entryPayload() throws {
        let both = entry(macA, 5, deleted: true)
        let neither = entry(macA, 5, value: nil)
        let notTrue = entry(macA, 5, value: nil, deleted: false)
        #expect(try refusal(file(["units": ["U": [both]]])) == .wrongStructure("entry"))
        #expect(try refusal(file(["units": ["U": [neither]]])) == .wrongStructure("entry"))
        #expect(try refusal(file(["units": ["U": [notTrue]]])) == .wrongStructure("entry"))
        #expect(try refusal(file(["units": ["U": [entry(macA, 5, value: nil, deleted: true)]]])) == nil)
    }

    @Test("Structural defects refuse the whole file")
    func structuralDefects() throws {
        #expect(try refusal(file(["mac": nil])) == .wrongStructure("mac"))
        #expect(try refusal(file(["mac": "not-a-mac"])) == .wrongStructure("mac"))
        #expect(try refusal(file(["mac": macA.rawValue.lowercased()])) == .wrongStructure("mac"))
        #expect(try refusal(file(["installation": ""])) == .wrongStructure("installation"))
        #expect(try refusal(file(["installation": String(repeating: "x", count: 65)])) == .wrongStructure("installation"))
        #expect(try refusal(file(["installation": 5])) == .wrongStructure("installation"))
        #expect(try refusal(file(["written": "yesterday"])) == .wrongStructure("written"))
        #expect(try refusal(file(["format": "1"])) == .wrongStructure("format"))
        #expect(try refusal(file(["format": 0])) == .wrongStructure("format"))
        #expect(try refusal(file(["context": [String: Any](), "units": ["U": "not a list"]])) == .wrongStructure("entries"))
        #expect(try refusal(file(["context": ["not-a-mac": 1]])) == .wrongStructure("context"))
        #expect(try refusal(file(["units": nil])) == .wrongStructure("units"))
        #expect(try refusal(file(["sets": ["S": [1, 2]]])) == .wrongStructure("sets"))
        #expect(try refusal(file(["entries": ["F": "x"]])) == .wrongStructure("entries"))
    }

    @Test("A value that is not a property-list value of holzBar refuses the file")
    func unrepresentableValue() throws {
        let nan = file(["units": ["U": [entry(macA, 5, value: Double.nan)]]])
        #expect(try refusal(nan) == .wrongStructure("values"))
    }

    // MARK: Pass-through

    @Test("Unknown top-level fields, units, families and entry fields survive decode and encode")
    func passThrough() throws {
        var unitEntry = entry(macA, 5, value: ["nested": [1, 2]])
        unitEntry["note"] = "kept"
        let original = file([
            "future": ["a": 1],
            "units": ["MysteryUnit": [unitEntry]],
            "entries": ["l26": ["bundle.id": [entry(macA, 4, value: [1, 2, 3])]]],
            "sets": ["Seen": ["b", "a"]],
            "context": [macA.rawValue: 5],
        ])
        let first = try decode(original).get()
        #expect(first.extra == ["future": .dictionary(["a": .integer(1)])])
        #expect(first.replica.live(.whole("MysteryUnit")).first?.extra == ["note": .string("kept")])
        #expect(first.replica.live(.split(family: "l26", item: "bundle.id")).count == 1)
        #expect(first.replica.sets == ["Seen": ["a", "b"]])

        let reencoded = try SyncDeviceFile.encode(first)
        let second = try SyncDeviceFile.decode(reencoded, fileName: "\(macA.rawValue).plist").get()
        #expect(second == first)
        #expect(second.replica.digest == first.replica.digest)
    }

    @Test("A contents value round-trips with every field")
    func roundTrip() throws {
        let replica = SyncReplica(
            context: SyncContext(counters: [macA: 9, macB: 3]),
            registers: [
                .whole("Zeta"): [SyncEntry(dot: SyncDot(mac: macA, n: 9), at: date, payload: .deleted)],
                .split(family: "Hotkeys", item: "ShowHidden"): [
                    SyncEntry(dot: SyncDot(mac: macB, n: 3), at: date, payload: .value(.array([.integer(1), .real(2.5)]))),
                    SyncEntry(dot: SyncDot(mac: macA, n: 7), at: date, payload: .value(.string("x")), extra: ["note": .bool(true)]),
                ],
            ],
            sets: ["Seen": ["one", "two"]]
        )
        let contents = SyncDeviceFile.Contents(unitTable: 1, mac: macA, installation: "abc", written: date, replica: replica, extra: ["future": .integer(4)])
        let data = try SyncDeviceFile.encode(contents)
        #expect(try SyncDeviceFile.decode(data, fileName: "\(macA.rawValue).plist").get() == contents)
    }

    // MARK: Names

    @Test("Only the exact device file name is a device file")
    func deviceFileNames() {
        let id = macA.rawValue
        #expect(SyncDeviceFile.isDeviceFileName("\(id).plist"))
        #expect(SyncDeviceFile.macID(fromFileName: "\(id).plist") == macA)
        let rejected = [
            ".DS_Store",
            "Icon\r",
            "\(id.lowercased()).plist",
            "\(id) 2.plist",
            "\(id) (conflicted copy 2026-10-07).plist",
            "\(id) (Christophs MacBook's conflicted copy 2026-10-07).plist",
            "\(id)-MacBook.plist",
            "\(id).sync-conflict-20261007-120000-ABCDEFG.plist",
            ".\(id).plist",
            ".syncthing.\(id).plist.tmp",
            ".\(id).plist.sb-1234",
            "\(id).plist.tmp",
            "\(id).PLIST",
            "Settings.plist",
            "",
        ]
        for name in rejected {
            #expect(!SyncDeviceFile.isDeviceFileName(name), "\(name.count) characters")
            #expect(SyncDeviceFile.macID(fromFileName: name) == nil)
        }
    }

    @Test("A conflict copy names the Mac whose file it copies")
    func conflictCopyOwner() {
        let id = macA.rawValue
        let known = [macA, macB]
        let copies = [
            "\(id) 2.plist",
            "\(id) (conflicted copy 2026-10-07).plist",
            "\(id)-MacBook.plist",
            "\(id).sync-conflict-20261007-120000-XYZ.plist",
        ]
        for name in copies {
            #expect(SyncDeviceFile.conflictCopyOwner(fileName: name, knownMacs: known) == macA)
        }
        #expect(SyncDeviceFile.conflictCopyOwner(fileName: "\(macB.rawValue) 2.plist", knownMacs: known) == macB)
        #expect(SyncDeviceFile.conflictCopyOwner(fileName: "\(id).plist", knownMacs: known) == nil)
        #expect(SyncDeviceFile.conflictCopyOwner(fileName: "\(id) 2.plist", knownMacs: [macB]) == nil)
        #expect(SyncDeviceFile.conflictCopyOwner(fileName: "Settings 2.plist", knownMacs: known) == nil)
        #expect(SyncDeviceFile.conflictCopyOwner(fileName: ".DS_Store", knownMacs: known) == nil)
        #expect(SyncDeviceFile.conflictCopyOwner(fileName: ".\(id) 2.plist", knownMacs: known) == nil)
    }
}
