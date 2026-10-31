//
//  PayloadInventory.swift
//  now-playing
//

import Foundation

/// What the probe writes about a playback notification's user info: the key names and value
/// types, which of the facts the module needs are present, and a redaction of text. Titles,
/// artists, albums and file names never leave this type unredacted.
public enum PayloadInventory {
    // The key names below are the `[ASSUMED]` keys of 38-CONTEXT.md, from memory of how
    // third-party tools read the two players' notifications. This probe checks them; nothing
    // here is a measured fact yet. Matching ignores case.
    static let nameKeys = ["name"]
    static let artistKeys = ["artist"]
    static let albumKeys = ["album"]
    static let durationKeys = ["total time", "duration"]
    static let positionKeys = ["playback position", "player position", "position"]
    static let locationKeys = ["location"]
    static let stateKeys = ["player state"]

    /// Which facts a payload carries.
    public struct Flags: Sendable, Equatable {
        public var hasName: Bool
        public var hasArtist: Bool
        public var hasAlbum: Bool
        public var hasDuration: Bool
        public var hasPosition: Bool
        public var hasLocation: Bool
        public var hasState: Bool

        public init(
            hasName: Bool = false, hasArtist: Bool = false, hasAlbum: Bool = false,
            hasDuration: Bool = false, hasPosition: Bool = false, hasLocation: Bool = false,
            hasState: Bool = false
        ) {
            self.hasName = hasName
            self.hasArtist = hasArtist
            self.hasAlbum = hasAlbum
            self.hasDuration = hasDuration
            self.hasPosition = hasPosition
            self.hasLocation = hasLocation
            self.hasState = hasState
        }

        /// The union of two sets of flags.
        func merged(with other: Flags) -> Flags {
            Flags(
                hasName: hasName || other.hasName, hasArtist: hasArtist || other.hasArtist,
                hasAlbum: hasAlbum || other.hasAlbum, hasDuration: hasDuration || other.hasDuration,
                hasPosition: hasPosition || other.hasPosition, hasLocation: hasLocation || other.hasLocation,
                hasState: hasState || other.hasState
            )
        }

        /// The six facts of the `has` field of a NOTIFY line, in the contract's order.
        public var has: String {
            let pairs: [(String, Bool)] = [
                ("name", hasName), ("artist", hasArtist), ("album", hasAlbum),
                ("duration", hasDuration), ("position", hasPosition), ("location", hasLocation),
            ]
            return pairs.map { "\($0.0):\($0.1 ? "y" : "n")" }.joined(separator: ",")
        }
    }

    /// Every key of the user info with the name of its value's type, sorted by key.
    public static func inventory(_ userInfo: [String: Any]) -> [(key: String, type: String)] {
        userInfo.keys.sorted().map { key in (key: key, type: typeName(userInfo[key] as Any)) }
    }

    /// The facts the inventory's keys say a payload carries.
    public static func flags(_ inventory: [(key: String, type: String)]) -> Flags {
        let keys = Set(inventory.map { $0.key.lowercased() })
        func has(_ candidates: [String]) -> Bool { candidates.contains { keys.contains($0) } }
        return Flags(
            hasName: has(nameKeys), hasArtist: has(artistKeys), hasAlbum: has(albumKeys),
            hasDuration: has(durationKeys), hasPosition: has(positionKeys),
            hasLocation: has(locationKeys), hasState: has(stateKeys)
        )
    }

    /// The `keys` field of a NOTIFY line: `key:type;key:type`.
    public static func describe(_ inventory: [(key: String, type: String)]) -> String {
        inventory.map { "\($0.key):\($0.type)" }.joined(separator: ";")
    }

    /// A string reduced to its length: `len=9`.
    public static func redacted(_ value: String) -> String {
        "len=\(value.count)"
    }

    /// The player state, only when it is one of the three words the players send.
    public static func state(in userInfo: [String: Any]) -> String? {
        for (key, value) in userInfo where stateKeys.contains(key.lowercased()) {
            guard let text = value as? String else { return nil }
            return ["Playing", "Paused", "Stopped"].contains(text) ? text : nil
        }
        return nil
    }

    static func typeName(_ value: Any) -> String {
        // A number that Foundation boxed (a notification's user info) keeps its kind in the
        // Objective-C type code; a Swift value is told apart by its own type.
        if type(of: value) is NSNumber.Type, let number = value as? NSNumber {
            switch String(cString: number.objCType) {
            case "c", "B": return "Bool"
            case "d", "f": return "Double"
            default: return "Int"
            }
        }
        switch value {
        case is String: return "String"
        case is Bool: return "Bool"
        case is Int, is Int8, is Int16, is Int32, is Int64, is UInt, is UInt8, is UInt16, is UInt32, is UInt64:
            return "Int"
        case is Double, is Float: return "Double"
        case is Date: return "Date"
        case is Data: return "Data"
        case is [Any]: return "Array"
        case is [String: Any]: return "Dictionary"
        default: return "Other"
        }
    }
}
