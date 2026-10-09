//
//  CanonicalPlist.swift
//  holzBar
//

import Foundation

/// Property-list writers whose bytes depend on the object alone. Foundation's writers order a dictionary the way its storage
/// does, which differs between two equal dictionaries, so the bytes of one seed would change from run to run. The fuzzing of the
/// codecs (`CodecFuzzTests`) writes its inputs with these, so a failing input is rebuilt from its seed, byte for byte, and the
/// byte-level damage it does to a file lands on the same bytes every time. Both formats are read back by Foundation in the tests.
enum CanonicalPlist {
    // MARK: XML

    static func xml(_ object: Any) -> Data? {
        var text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        text += "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">"
        guard write(object, to: &text) else { return nil }
        text += "</plist>\n"
        return Data(text.utf8)
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func isValid(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { $0.value >= 0x20 || $0 == "\n" || $0 == "\t" }
    }

    private static func real(_ value: Double) -> String {
        value.isNaN ? "nan" : value.isInfinite ? (value < 0 ? "-infinity" : "+infinity") : "\(value)"
    }

    private static func write(_ object: Any, to text: inout String) -> Bool {
        switch Scalar(object) {
        case .dictionary(let dictionary):
            text += "<dict>"
            for key in dictionary.keys.sorted() {
                guard isValid(key), let value = dictionary[key] else { return false }
                text += "<key>\(escaped(key))</key>"
                guard write(value, to: &text) else { return false }
            }
            text += "</dict>"
        case .array(let array):
            text += "<array>"
            for element in array { guard write(element, to: &text) else { return false } }
            text += "</array>"
        case .string(let value):
            guard isValid(value) else { return false }
            text += "<string>\(escaped(value))</string>"
        case .data(let value):
            text += "<data>\(value.base64EncodedString())</data>"
        case .date(let value):
            text += "<date>\(ISO8601DateFormatter().string(from: value))</date>"
        case .bool(let value):
            text += value ? "<true/>" : "<false/>"
        case .integer(let value):
            text += "<integer>\(value)</integer>"
        case .real(let value):
            text += "<real>\(real(value))</real>"
        case nil:
            return false
        }
        return true
    }

    // MARK: Binary

    /// A binary property list (bplist00): the objects in the order of a walk that sorts every dictionary's keys, every integer
    /// as eight bytes.
    static func binary(_ object: Any) -> Data? {
        enum Node {
            case scalar([UInt8])
            case array([Int])
            case dictionary([Int], [Int])
        }
        var nodes: [Node] = []
        func add(_ object: Any) -> Int? {
            let index = nodes.count
            nodes.append(.scalar([]))
            switch Scalar(object) {
            case .dictionary(let dictionary):
                var keyReferences: [Int] = []
                var valueReferences: [Int] = []
                for key in dictionary.keys.sorted() {
                    guard let keyReference = add(key), let value = dictionary[key], let valueReference = add(value) else { return nil }
                    keyReferences.append(keyReference)
                    valueReferences.append(valueReference)
                }
                nodes[index] = .dictionary(keyReferences, valueReferences)
            case .array(let array):
                var references: [Int] = []
                for element in array {
                    guard let reference = add(element) else { return nil }
                    references.append(reference)
                }
                nodes[index] = .array(references)
            case .string(let value):
                let utf8 = Array(value.utf8)
                if utf8.allSatisfy({ $0 < 0x80 }) {
                    nodes[index] = .scalar(header(0x50, utf8.count) + utf8)
                } else {
                    let units = Array(value.utf16)
                    nodes[index] = .scalar(header(0x60, units.count) + units.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
                }
            case .data(let value):
                nodes[index] = .scalar(header(0x40, value.count) + [UInt8](value))
            case .date(let value):
                nodes[index] = .scalar([0x33] + bigEndian(value.timeIntervalSinceReferenceDate.bitPattern, bytes: 8))
            case .bool(let value):
                nodes[index] = .scalar([value ? 0x09 : 0x08])
            case .integer(let value):
                nodes[index] = .scalar([0x13] + bigEndian(UInt64(bitPattern: value), bytes: 8))
            case .real(let value):
                nodes[index] = .scalar([0x23] + bigEndian(value.bitPattern, bytes: 8))
            case nil:
                return nil
            }
            return index
        }
        guard add(object) != nil else { return nil }
        let referenceSize = nodes.count > 255 ? 2 : 1
        func reference(_ value: Int) -> [UInt8] {
            referenceSize == 1 ? [UInt8(value)] : bigEndian(UInt64(value), bytes: 2)
        }
        var body: [UInt8] = Array("bplist00".utf8)
        var offsets: [Int] = []
        for node in nodes {
            offsets.append(body.count)
            switch node {
            case .scalar(let bytes):
                body += bytes
            case .array(let references):
                body += header(0xA0, references.count) + references.flatMap(reference)
            case .dictionary(let keys, let values):
                body += header(0xD0, keys.count) + keys.flatMap(reference) + values.flatMap(reference)
            }
        }
        let offsetSize = body.count > 0xFFFF ? 4 : body.count > 0xFF ? 2 : 1
        let tableStart = body.count
        for offset in offsets { body += bigEndian(UInt64(offset), bytes: offsetSize) }
        var trailer = [UInt8](repeating: 0, count: 6) + [UInt8(offsetSize), UInt8(referenceSize)]
        for value in [nodes.count, 0, tableStart] { trailer += bigEndian(UInt64(value), bytes: 8) }
        return Data(body + trailer)
    }

    private static func bigEndian(_ value: UInt64, bytes: Int) -> [UInt8] {
        (0..<bytes).map { UInt8((value >> UInt64((bytes - 1 - $0) * 8)) & 0xFF) }
    }

    /// The marker of a collection or a string with `count` members: the count in the low nibble, or an integer object after it.
    private static func header(_ marker: UInt8, _ count: Int) -> [UInt8] {
        count < 15 ? [marker | UInt8(count)] : [marker | 0x0F, 0x13] + bigEndian(UInt64(count), bytes: 8)
    }

    // MARK: Reading an object

    private enum Scalar {
        case dictionary([String: Any])
        case array([Any])
        case string(String)
        case data(Data)
        case date(Date)
        case bool(Bool)
        case integer(Int64)
        case real(Double)

        init?(_ object: Any) {
            if let value = object as? [String: Any] {
                self = .dictionary(value)
            } else if let value = object as? [Any] {
                self = .array(value)
            } else if let value = object as? String {
                self = .string(value)
            } else if let value = object as? Data {
                self = .data(value)
            } else if let value = object as? Date {
                self = .date(value)
            } else if let number = object as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    self = .bool(number.boolValue)
                } else if CFNumberIsFloatType(number) {
                    self = .real(number.doubleValue)
                } else {
                    self = .integer(number.int64Value)
                }
            } else if let value = object as? Bool {
                self = .bool(value)
            } else if let value = object as? Int {
                self = .integer(Int64(value))
            } else if let value = object as? Int64 {
                self = .integer(value)
            } else if let value = object as? Double {
                self = .real(value)
            } else {
                return nil
            }
        }
    }
}
