//
//  DDCCapabilities.swift
//  holzBar
//

import Foundation

/// The capabilities string of a monitor: which controls it lists, read in fragments over DDC/CI.
///
/// Every byte of it comes from monitor firmware and is not trusted. ``fragment(_:expectingOffset:)``
/// accepts a fragment only after its length byte, address, checksum, opcode and echoed offset
/// are right; ``Assembler`` keeps at most ``maximumFragments`` of them; ``parse(_:)`` walks the
/// text without recursion and gives up on anything that does not balance. The string is a
/// hint, not the truth: a monitor may leave out controls it answers or carry vendor tokens, so
/// the module confirms every control by reading its value. Only the four controls of
/// ``DDCControl`` can ever become a candidate, whatever the string lists.
nonisolated enum DDCCapabilities {
    /// The most fragments read for one string, so a monitor that never ends it keeps at most 640
    /// bytes in memory.
    static let maximumFragments = 20

    /// The data bytes of one reply to a capabilities request, or `nil` when the reply is not a
    /// valid fragment for `offset`. An empty array is the valid terminator, a fragment without
    /// data.
    ///
    /// A fragment is `[0x6E, 0x80 | length, 0xE3, offset (2), data..., checksum]`, where the
    /// length counts the opcode, the offset and the data, so the data is at most 32 bytes. The
    /// checksum starts from 0x50 and takes in every byte before it.
    static func fragment(_ bytes: [UInt8], expectingOffset offset: UInt16) -> [UInt8]? {
        guard bytes.count >= 6, bytes[0] == 0x6E, bytes[1] & 0x80 != 0 else {
            return nil
        }
        let length = Int(bytes[1] & 0x7F)
        guard length >= 3, length + 3 <= bytes.count else {
            return nil
        }
        let checksum = bytes[0..<(length + 2)].reduce(0x50, ^)
        guard checksum == bytes[length + 2], bytes[2] == 0xE3 else {
            return nil
        }
        guard (UInt16(bytes[3]) << 8 | UInt16(bytes[4])) == offset else {
            return nil
        }
        let count = length - 3
        guard count <= 32 else {
            return nil
        }
        return Array(bytes[5..<(5 + count)])
    }

    /// Puts the fragments of one string together, from offset 0.
    struct Assembler: Equatable, Sendable {
        private var data = [UInt8]()
        private var fragments = 0
        private var ended = false

        init() {}

        /// The offset to request next: the number of data bytes kept so far.
        var nextOffset: UInt16 {
            UInt16(data.count)
        }

        /// Whether the string is finished: a fragment without data came, the parentheses of the
        /// text balance after at least one opening, or ``maximumFragments`` were kept.
        var isComplete: Bool {
            if ended || fragments >= DDCCapabilities.maximumFragments {
                return true
            }
            var depth = 0
            var opened = false
            for byte in data {
                if byte == 0x28 {
                    depth += 1
                    opened = true
                } else if byte == 0x29 {
                    depth -= 1
                }
            }
            return opened && depth <= 0
        }

        /// Keeps the data of one valid fragment. An empty one ends the string; nothing is kept
        /// once the string is complete.
        mutating func append(_ fragment: [UInt8]) {
            guard !isComplete else {
                return
            }
            fragments += 1
            if fragment.isEmpty {
                ended = true
            } else {
                data.append(contentsOf: fragment)
            }
        }

        /// The string so far as ASCII: NUL bytes are removed, bytes above 0x7F dropped.
        var text: String {
            String(bytes: data.filter { $0 != 0 && $0 < 0x80 }, encoding: .ascii) ?? ""
        }
    }

    /// The VCP codes in the `vcp(...)` group of a capabilities string, or `nil` when there is no
    /// such group, its parentheses never balance or it lists nothing, so the caller falls back
    /// to reading the controls directly.
    ///
    /// The group is found case-insensitively. At its top level every token of two hex digits,
    /// in either case and split by any whitespace, is a code; a code followed by a group of
    /// sub-values (`14(01 05 08 0B)`) keeps the code and skips the group; every other token is
    /// ignored.
    static func parse(_ string: String) -> Set<UInt8>? {
        let text = Array(string.utf8).map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
        let marker = Array("vcp(".utf8)
        guard text.count >= marker.count else {
            return nil
        }
        var start: Int?
        for index in 0...(text.count - marker.count) where text[index..<(index + marker.count)].elementsEqual(marker) {
            start = index + marker.count
            break
        }
        guard let start else {
            return nil
        }
        var codes = Set<UInt8>()
        var token = [UInt8]()
        func flush() {
            if token.count == 2, let high = hexValue(token[0]), let low = hexValue(token[1]) {
                codes.insert(high << 4 | low)
            }
            token.removeAll(keepingCapacity: true)
        }
        var depth = 1
        for byte in text[start...] {
            switch byte {
            case 0x28:
                if depth == 1 {
                    flush()
                }
                depth += 1
            case 0x29:
                if depth == 1 {
                    flush()
                }
                depth -= 1
                if depth == 0 {
                    return codes.isEmpty ? nil : codes
                }
            case 0x09, 0x0A, 0x0D, 0x20:
                if depth == 1 {
                    flush()
                }
            default:
                if depth == 1 {
                    token.append(byte)
                }
            }
        }
        return nil
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x61...0x66: byte - 0x61 + 10
        default: nil
        }
    }

    /// The controls to read, in the order brightness, contrast, volume, mute: those of the
    /// four that the string lists. `nil` when the string was not read, or lists none of the
    /// four, so the caller reads the controls directly instead.
    static func candidates(listed: Set<UInt8>?) -> [DDCControl]? {
        guard let listed else {
            return nil
        }
        let found = DDCControl.allCases.filter { listed.contains($0.rawValue) }
        return found.isEmpty ? nil : found
    }

    /// The rows a monitor's card shows, for the controls that were confirmed by a value read:
    /// brightness, contrast and volume, in this order. Mute never has a row of its own.
    static func rows(confirmed: Set<DDCControl>) -> [DDCControl] {
        [.brightness, .contrast, .volume].filter { confirmed.contains($0) }
    }

    /// Whether the volume row carries a mute button: the monitor confirmed mute and volume.
    static func showsMute(confirmed: Set<DDCControl>) -> Bool {
        confirmed.contains(.volume) && confirmed.contains(.mute)
    }
}
