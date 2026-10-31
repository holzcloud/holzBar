//
//  AccessoryDevice.swift
//  holzBar
//

import Foundation

/// What kind of accessory a paired Bluetooth device is, from its class of device.
///
/// The kind only chooses the symbol; every kind is treated alike (see ``AccessoryDevice``).
nonisolated enum AccessoryKind: Sendable, CaseIterable {
    case headphones
    case speaker
    case keyboard
    case pointer
    case other

    /// The kind for a Bluetooth class of device. The major class 4 is audio and video: the minor
    /// classes 1, 2 and 6 are a headset, a hands-free device and headphones, 5 and 8 a loudspeaker
    /// and a portable audio device. The major class 5 is a peripheral, whose minor class carries
    /// the keyboard flag (0x10) and the pointing flag (0x20). Anything else, and any value that is
    /// not a byte, is ``other``.
    init(majorClass: Int, minorClass: Int) {
        guard (0...255).contains(majorClass), (0...255).contains(minorClass) else {
            self = .other
            return
        }
        switch (majorClass, minorClass) {
        case (4, 1), (4, 2), (4, 6):
            self = .headphones
        case (4, 5), (4, 8):
            self = .speaker
        case (5, 0x10), (5, 0x30):
            self = .keyboard
        case (5, 0x20):
            self = .pointer
        default:
            self = .other
        }
    }
}

/// A paired Bluetooth device that is connected, as the accessory alerts see it.
///
/// The id is the device's Bluetooth address, hyphenated and lowercase. It and the name are
/// personal identifiers of the user's own devices (people name their AirPods after themselves),
/// so a value lives in memory only while the module runs and is never stored, logged or exported.
nonisolated struct AccessoryDevice: Equatable, Hashable, Sendable, Identifiable {
    /// The most bytes of a name.
    static let maximumNameBytes = 80

    /// The Bluetooth address in the form "aa-bb-cc-dd-ee-ff".
    let id: String
    let name: String
    let kind: AccessoryKind

    /// Creates a device from what IOBluetooth reports, or returns `nil` when the address is not
    /// six pairs of hexadecimal digits. The name is trimmed and cut to ``maximumNameBytes`` bytes
    /// without splitting a character; an empty name becomes the address.
    init?(address: String, name: String, majorClass: Int, minorClass: Int) {
        guard let id = Self.normalizedAddress(address) else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = trimmed.isEmpty ? id : Self.cut(trimmed)
        self.kind = AccessoryKind(majorClass: majorClass, minorClass: minorClass)
    }

    /// The symbol: the AirPods symbols for a name that says so, else the one of the kind.
    var symbolName: String {
        let lowered = name.lowercased()
        if lowered.contains("airpods pro") {
            return "airpodspro"
        }
        if lowered.contains("airpods") {
            return "airpods"
        }
        switch kind {
        case .headphones: return "headphones"
        case .speaker: return "speaker.wave.2"
        case .keyboard: return "keyboard"
        case .pointer: return "computermouse"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    /// The address in the form "aa-bb-cc-dd-ee-ff", or `nil` for anything that is not six pairs
    /// of hexadecimal digits separated by hyphens or by colons (one kind of separator).
    static func normalizedAddress(_ raw: String) -> String? {
        for separator in ["-", ":"] {
            let parts = raw.components(separatedBy: separator)
            guard parts.count == 6 else {
                continue
            }
            let isAddress = parts.allSatisfy { part in
                part.utf8.count == 2 && part.utf8.allSatisfy { $0.isHexDigit }
            }
            if isAddress {
                return parts.map { $0.lowercased() }.joined(separator: "-")
            }
        }
        return nil
    }

    private static func cut(_ name: String) -> String {
        var result = ""
        var bytes = 0
        for character in name {
            let size = String(character).utf8.count
            if bytes + size > maximumNameBytes {
                break
            }
            result.append(character)
            bytes += size
        }
        return result
    }
}

private extension UInt8 {
    /// Whether the byte is an ASCII hexadecimal digit.
    nonisolated var isHexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}
