//
//  SyncValue.swift
//  holzBar
//

import CryptoKit
import Foundation

/// A SHA-256 digest, as 64 lower-case hexadecimal characters.
///
/// Digests identify values and states in the sync engine: two values are the same value
/// when their digests are equal. They are also what the sync state remembers instead of
/// the values themselves.
nonisolated struct SyncDigest: Hashable, Comparable, Sendable {
    /// The digest as lower-case hexadecimal characters.
    let hex: String

    /// Marks a captured absent value: the local defaults held nothing for the unit.
    static let unset = SyncDigest(hex: "unset")

    /// The digest of `bytes`.
    static func hash(_ bytes: [UInt8]) -> SyncDigest {
        var characters: [UInt8] = []
        characters.reserveCapacity(2 * SHA256.byteCount)
        for byte in SHA256.hash(data: bytes) {
            characters.append(hexDigits[Int(byte >> 4)])
            characters.append(hexDigits[Int(byte & 0x0F)])
        }
        return SyncDigest(hex: String(bytes: characters, encoding: .utf8) ?? "")
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    static func < (lhs: SyncDigest, rhs: SyncDigest) -> Bool {
        lhs.hex.utf8.lexicographicallyPrecedes(rhs.hex.utf8)
    }
}

/// A property-list value, as a closed Swift type.
///
/// Every setting the sync engine moves is a property-list value. The type keeps the
/// distinctions the property-list format keeps (a boolean, an integer and a real number are
/// three different values) and has a canonical digest, so equal values are equal whatever
/// the insertion order of their dictionaries.
nonisolated enum SyncValue: Hashable, Sendable {
    case bool(Bool)
    case integer(Int64)
    case real(Double)
    case string(String)
    case data(Data)
    case date(Date)
    case array([SyncValue])
    case dictionary([String: SyncValue])

    /// How deep values may nest. Real settings nest two or three levels.
    static let maximumDepth = 32

    /// Converts a property-list object, or returns `nil` when it holds anything a property
    /// list does not, a number that does not fit (an integer above `Int64.max`, a number that
    /// is not finite) or nests deeper than ``maximumDepth``.
    init?(propertyList object: Any) {
        self.init(propertyList: object, depth: 0)
    }

    private init?(propertyList object: Any, depth: Int) {
        guard depth <= Self.maximumDepth else {
            return nil
        }
        if let string = object as? String {
            self = .string(string)
        } else if let data = object as? Data {
            self = .data(data)
        } else if let date = object as? Date {
            guard date.timeIntervalSinceReferenceDate.isFinite else {
                return nil
            }
            self = .date(date)
        } else if let array = object as? [Any] {
            var values: [SyncValue] = []
            values.reserveCapacity(array.count)
            for element in array {
                guard let value = SyncValue(propertyList: element, depth: depth + 1) else {
                    return nil
                }
                values.append(value)
            }
            self = .array(values)
        } else if let dictionary = object as? [String: Any] {
            var values: [String: SyncValue] = [:]
            values.reserveCapacity(dictionary.count)
            // sync-lint: ordered every key is assigned to its own key of a dictionary, and any invalid item gives nil
            for (key, element) in dictionary {
                guard let value = SyncValue(propertyList: element, depth: depth + 1) else {
                    return nil
                }
                values[key] = value
            }
            self = .dictionary(values)
        } else if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                let double = number.doubleValue
                guard double.isFinite else {
                    return nil
                }
                self = .real(double)
            } else {
                // An unsigned 64-bit integer above `Int64.max` does not fit.
                if String(cString: number.objCType) == "Q", number.uint64Value > UInt64(Int64.max) {
                    return nil
                }
                self = .integer(number.int64Value)
            }
        } else {
            return nil
        }
    }

    /// The value as an object `PropertyListSerialization` writes.
    var propertyList: Any {
        switch self {
        case .bool(let value):
            value
        case .integer(let value):
            value
        case .real(let value):
            value
        case .string(let value):
            value
        case .data(let value):
            value
        case .date(let value):
            value
        case .array(let values):
            values.map(\.propertyList)
        case .dictionary(let values):
            values.mapValues(\.propertyList)
        }
    }

    // MARK: Accessors

    /// The boolean, if this value is one.
    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// The integer, if this value is one.
    var integerValue: Int64? {
        if case .integer(let value) = self {
            return value
        }
        return nil
    }

    /// The string, if this value is one.
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    /// The date, if this value is one.
    var dateValue: Date? {
        if case .date(let value) = self {
            return value
        }
        return nil
    }

    /// The elements, if this value is an array.
    var arrayValue: [SyncValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    /// The members, if this value is a dictionary.
    var dictionaryValue: [String: SyncValue]? {
        if case .dictionary(let value) = self {
            return value
        }
        return nil
    }

    // MARK: Digest and Size

    /// The canonical digest: SHA-256 over a type-tagged, length-prefixed encoding in which
    /// dictionary keys are sorted by their UTF-8 bytes. Equal values digest equal whatever
    /// the order their dictionaries were built in; an integer, a real number and a
    /// boolean of the same magnitude digest differently.
    var digest: SyncDigest {
        var bytes: [UInt8] = []
        appendCanonicalEncoding(to: &bytes)
        return SyncDigest.hash(bytes)
    }

    /// An estimate of the size in bytes, for caps. It is not the size of any file format.
    var encodedSize: Int {
        switch self {
        case .bool:
            1
        case .integer, .real, .date:
            8
        case .string(let value):
            value.utf8.count + 4
        case .data(let value):
            value.count + 4
        case .array(let values):
            values.reduce(4) { $0 + $1.encodedSize }
        case .dictionary(let values):
            values.reduce(4) { $0 + $1.key.utf8.count + 4 + $1.value.encodedSize }
        }
    }

    /// Appends the canonical encoding of the value to `bytes`.
    func appendCanonicalEncoding(to bytes: inout [UInt8]) {
        switch self {
        case .bool(let value):
            bytes.append(0x01)
            bytes.append(value ? 1 : 0)
        case .integer(let value):
            bytes.append(0x02)
            Self.append(UInt64(bitPattern: value), to: &bytes)
        case .real(let value):
            bytes.append(0x03)
            // Zero and negative zero are equal values, so they digest equal.
            Self.append(value == 0 ? 0 : value.bitPattern, to: &bytes)
        case .string(let value):
            bytes.append(0x04)
            Self.append(value.utf8, to: &bytes)
        case .data(let value):
            bytes.append(0x05)
            Self.append(value, to: &bytes)
        case .date(let value):
            bytes.append(0x06)
            let interval = value.timeIntervalSinceReferenceDate
            Self.append(interval == 0 ? 0 : interval.bitPattern, to: &bytes)
        case .array(let values):
            bytes.append(0x07)
            Self.append(UInt64(values.count), to: &bytes)
            for value in values {
                value.appendCanonicalEncoding(to: &bytes)
            }
        case .dictionary(let values):
            bytes.append(0x08)
            Self.append(UInt64(values.count), to: &bytes)
            for key in values.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                Self.append(key.utf8, to: &bytes)
                values[key]?.appendCanonicalEncoding(to: &bytes)
            }
        }
    }

    private static func append(_ number: UInt64, to bytes: inout [UInt8]) {
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: number >> UInt64(shift)))
        }
    }

    private static func append<Bytes: Collection>(_ content: Bytes, to bytes: inout [UInt8]) where Bytes.Element == UInt8 {
        append(UInt64(content.count), to: &bytes)
        bytes.append(contentsOf: content)
    }
}
