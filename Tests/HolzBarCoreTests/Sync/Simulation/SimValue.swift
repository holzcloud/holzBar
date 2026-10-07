import CryptoKit
import Foundation

/// The simulator's value type for one defaults value or file entry.
///
/// Every user change writes a fresh token (`u<k>@<unit>`), every automatic change an
/// `auto-<mac>-<k>` token, and a value present before a Mac's first redesigned run is
/// `pre(<mac>)` (A2 section 2.3). The value at any place then names the event that made it.
enum SimValue: Hashable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case data(Data)
    case array([SimValue])
    case dictionary([String: SimValue])

    // MARK: Tokens

    static func userToken(_ k: Int, unit: String) -> SimValue { .string("u\(k)@\(unit)") }
    static func autoToken(mac: SimMacName, _ k: Int) -> SimValue { .string("auto-\(mac.name)-\(k)") }
    static func preToken(mac: SimMacName) -> SimValue { .string("pre(\(mac.name))") }

    /// Where a token string came from.
    enum Origin: Hashable, Sendable {
        case user(k: Int, unit: String)
        case automatic(mac: String, k: Int)
        case pre(mac: String)
    }

    /// Parses a token string, or returns `nil` when the string is not a token.
    static func origin(ofToken token: String) -> Origin? {
        if token.hasPrefix("u"), let at = token.firstIndex(of: "@") {
            let digits = token[token.index(after: token.startIndex)..<at]
            if !digits.isEmpty, let k = Int(digits) {
                return .user(k: k, unit: String(token[token.index(after: at)...]))
            }
        }
        if token.hasPrefix("auto-") {
            let rest = token.dropFirst(5)
            if let dash = rest.lastIndex(of: "-"), let k = Int(rest[rest.index(after: dash)...]) {
                return .automatic(mac: String(rest[..<dash]), k: k)
            }
        }
        if token.hasPrefix("pre("), token.hasSuffix(")") {
            return .pre(mac: String(token.dropFirst(4).dropLast()))
        }
        return nil
    }

    /// Every token string inside the value, in sorted order. JSON-shaped `data` is decoded.
    var tokens: [String] {
        var found = Set<String>()
        collectTokens(into: &found)
        return found.sorted()
    }

    private func collectTokens(into found: inout Set<String>) {
        switch self {
        case .string(let text):
            if Self.origin(ofToken: text) != nil { found.insert(text) }
        case .int, .bool:
            break
        case .data(let bytes):
            if let object = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]),
               let value = SimValue(propertyList: object) {
                value.collectTokens(into: &found)
            }
        case .array(let elements):
            for element in elements { element.collectTokens(into: &found) }
        case .dictionary(let entries):
            for key in entries.keys.sorted() { entries[key]?.collectTokens(into: &found) }
        }
    }

    // MARK: Property list bridge

    /// The value as a property-list object (`String`, `Int`, `Bool`, `Data`, `[Any]`, `[String: Any]`).
    var propertyList: Any {
        switch self {
        case .string(let text): text
        case .int(let number): number
        case .bool(let flag): flag
        case .data(let bytes): bytes
        case .array(let elements): elements.map(\.propertyList)
        case .dictionary(let entries): entries.mapValues(\.propertyList)
        }
    }

    /// Converts a property-list (or JSON) object. Returns `nil` for types the simulator has no case
    /// for (dates, doubles that are not whole numbers, `NSNull`).
    init?(propertyList object: Any) {
        switch object {
        case let text as String:
            self = .string(text)
        case let bytes as Data:
            self = .data(bytes)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                let double = number.doubleValue
                guard double == double.rounded(), abs(double) < 1e15 else { return nil }
                self = .int(Int(double))
            } else {
                self = .int(number.intValue)
            }
        case let flag as Bool:
            self = .bool(flag)
        case let number as Int:
            self = .int(number)
        case let elements as [Any]:
            var converted: [SimValue] = []
            for element in elements {
                guard let value = SimValue(propertyList: element) else { return nil }
                converted.append(value)
            }
            self = .array(converted)
        case let entries as [String: Any]:
            var converted: [String: SimValue] = [:]
            for (key, element) in entries {
                guard let value = SimValue(propertyList: element) else { return nil }
                converted[key] = value
            }
            self = .dictionary(converted)
        default:
            return nil
        }
    }

    // MARK: Canonical rendering

    /// A canonical text form: dictionary keys sorted, no platform-dependent formatting.
    /// The trace hash and every equality of "encoded" content use it, never raw plist bytes.
    var canonical: String {
        switch self {
        case .string(let text): "\"\(text)\""
        case .int(let number): "\(number)"
        case .bool(let flag): flag ? "true" : "false"
        case .data(let bytes): "data:\(SimDigest.hex(of: bytes))"
        case .array(let elements): "[" + elements.map(\.canonical).joined(separator: ",") + "]"
        case .dictionary(let entries):
            "{" + entries.keys.sorted().map { "\($0):\(entries[$0]!.canonical)" }.joined(separator: ",") + "}"
        }
    }

    /// The same shape the type has as a defaults value kind (used by schema checks of the old peer).
    enum Kind: Sendable { case scalar, array, dictionary, data }

    var kind: Kind {
        switch self {
        case .string, .int, .bool: .scalar
        case .array: .array
        case .dictionary: .dictionary
        case .data: .data
        }
    }
}

/// SHA-256 helpers over bytes and text, used for the trace hash and for opaque content in traces.
enum SimDigest {
    static func hex(of bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func hex(of text: String) -> String {
        hex(of: Data(text.utf8))
    }

    /// A canonical, platform-independent rendering of file content for the trace: a decoded property list
    /// (dates in whole milliseconds, dictionary keys sorted) or the SHA-256 of the raw bytes.
    static func canonicalRendering(of content: Data) -> String {
        guard let object = try? PropertyListSerialization.propertyList(from: content, options: [], format: nil) else {
            return "bytes:\(content.count):\(hex(of: content))"
        }
        return "plist:" + render(object)
    }

    private static func render(_ object: Any) -> String {
        switch object {
        case let date as Date:
            return "date:\(Int64((date.timeIntervalSince1970 * 1000).rounded()))"
        case let entries as [String: Any]:
            return "{" + entries.keys.sorted().map { "\($0):\(render(entries[$0]!))" }.joined(separator: ",") + "}"
        case let elements as [Any]:
            return "[" + elements.map(render).joined(separator: ",") + "]"
        default:
            if let value = SimValue(propertyList: object) { return value.canonical }
            return "?"
        }
    }
}
