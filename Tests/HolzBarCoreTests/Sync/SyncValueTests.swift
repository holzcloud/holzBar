//
//  SyncValueTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncValue")
struct SyncValueTests {
    @Test("Dictionaries digest equal whatever order they were built in")
    func digestIgnoresInsertionOrder() {
        let keys = (0..<40).map { "key\($0)" }
        var forward: [String: SyncValue] = [:]
        var backward: [String: SyncValue] = [:]
        for key in keys {
            forward[key] = .integer(Int64(key.count))
        }
        for key in keys.reversed() {
            backward[key] = .integer(Int64(key.count))
        }
        #expect(SyncValue.dictionary(forward).digest == SyncValue.dictionary(backward).digest)
    }

    @Test("An integer, a real number and a boolean digest differently")
    func digestSeparatesTypes() {
        let digests: Set<SyncDigest> = [
            SyncValue.integer(1).digest,
            SyncValue.real(1).digest,
            SyncValue.bool(true).digest,
            SyncValue.string("1").digest,
            SyncValue.array([.integer(1)]).digest,
        ]
        #expect(digests.count == 5)
    }

    @Test("Zero and negative zero are the same value")
    func negativeZero() {
        #expect(SyncValue.real(0).digest == SyncValue.real(-0.0).digest)
    }

    @Test("A property list converts and converts back unchanged")
    func propertyListRoundTrip() throws {
        let date = Date(timeIntervalSinceReferenceDate: 12345)
        let object: [String: Any] = [
            "flag": true,
            "count": 3,
            "ratio": 0.5,
            "name": "holz",
            "blob": Data([1, 2, 3]),
            "when": date,
            "list": [1, "two", false],
            "nested": ["inner": [1.5]],
        ]
        let value = try #require(SyncValue(propertyList: object))
        let expected: SyncValue = .dictionary([
            "flag": .bool(true),
            "count": .integer(3),
            "ratio": .real(0.5),
            "name": .string("holz"),
            "blob": .data(Data([1, 2, 3])),
            "when": .date(date),
            "list": .array([.integer(1), .string("two"), .bool(false)]),
            "nested": .dictionary(["inner": .array([.real(1.5)])]),
        ])
        #expect(value == expected)
        #expect(SyncValue(propertyList: value.propertyList) == value)
    }

    @Test("A plist reader keeps booleans and integers apart")
    func booleansAndIntegersStayApart() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["a": true, "b": 1, "c": 1.0], format: .binary, options: 0)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let value = try #require(SyncValue(propertyList: object))
        #expect(value == .dictionary(["a": .bool(true), "b": .integer(1), "c": .real(1)]))
    }

    @Test("Values a property list cannot hold are refused")
    func refusesForeignValues() {
        #expect(SyncValue(propertyList: Double.nan) == nil)
        #expect(SyncValue(propertyList: Double.infinity) == nil)
        #expect(SyncValue(propertyList: UInt64.max) == nil)
        #expect(SyncValue(propertyList: URL(filePath: "/tmp")) == nil)
        #expect(SyncValue(propertyList: [1: "x"]) == nil)
        #expect(SyncValue(propertyList: ["x": NSNull()]) == nil)
    }

    @Test("Values nested too deeply are refused")
    func refusesDeepNesting() {
        var object: Any = 1
        for _ in 0..<(SyncValue.maximumDepth + 2) {
            object = [object]
        }
        #expect(SyncValue(propertyList: object) == nil)
        var shallow: Any = 1
        for _ in 0..<5 {
            shallow = [shallow]
        }
        #expect(SyncValue(propertyList: shallow) != nil)
    }

    @Test("The size estimate grows with the content")
    func sizeEstimate() {
        #expect(SyncValue.data(Data(count: 1000)).encodedSize > SyncValue.data(Data(count: 10)).encodedSize)
        #expect(SyncValue.array([.string("abc"), .string("abc")]).encodedSize > SyncValue.string("abc").encodedSize)
    }
}
