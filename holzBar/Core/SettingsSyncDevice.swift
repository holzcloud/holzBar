//
//  SettingsSyncDevice.swift
//  holzBar
//

import CryptoKit
import Foundation

/// Decides which Mac wrote a settings sync file.
///
/// Each Mac identifies itself by a UUID that it creates once and keeps in its own defaults;
/// the id is never exported, imported or synced. Older holzBar builds wrote only the
/// computer name, and later ones both; holzBar no longer writes the name, which usually
/// holds the owner's name, but still reads it from the files of older builds.
///
/// Migration Assistant, a restore or a clone copies the defaults, and with them the id,
/// so the id is tied to the Mac by a salted SHA-256 of its hardware UUID
/// (``hardwareHash(of:salt:)``), kept beside it. The hardware UUID itself never leaves the
/// Mac and is never stored; a Mac whose hash does not match gets a new id (F-38).
nonisolated enum SettingsSyncDevice {
    /// The key of the writing Mac's id in the sync file.
    static let deviceIDKey = "deviceID"

    /// The key of the writing Mac's computer name in the sync files of older builds; read,
    /// never written.
    static let deviceNameKey = "device"

    /// Whether the sync file was written by this Mac.
    ///
    /// An id in the file decides alone, so two Macs with the same name are told apart. Only a
    /// file without an id, written by an older holzBar, falls back to the name, and only
    /// when this Mac has a non-empty computer name.
    ///
    /// - Parameters:
    ///   - file: The contents of the sync file.
    ///   - deviceID: This Mac's id.
    ///   - computerName: This Mac's computer name, if it has one.
    static func isFromThisMac(file: [String: Any], deviceID: String, computerName: String?) -> Bool {
        if let fileDeviceID = file[deviceIDKey] as? String {
            return fileDeviceID == deviceID
        }
        guard let computerName, !computerName.isEmpty else {
            return false
        }
        return (file[deviceNameKey] as? String) == computerName
    }

    // MARK: Hardware Identity

    /// Whether the defaults that hold the sync id belong to this Mac.
    nonisolated enum Identity: Equatable, Sendable {
        /// The stored hash is this Mac's.
        case same
        /// No hash is stored yet.
        case firstSeen
        /// The stored hash is another Mac's: the defaults were copied from it.
        case otherMac
        /// This Mac's hardware UUID could not be read.
        case unknown
    }

    /// Decides whether the defaults that hold the sync id belong to this Mac.
    ///
    /// - Parameters:
    ///   - storedHash: The hash stored beside the sync id, if any.
    ///   - salt: The salt stored beside it, if any.
    ///   - hardwareID: This Mac's hardware UUID, if it could be read.
    static func identity(storedHash: String?, salt: Data?, hardwareID: String?) -> Identity {
        guard let hardwareID else {
            return .unknown
        }
        guard let storedHash, let salt else {
            return .firstSeen
        }
        return hardwareHash(of: hardwareID, salt: salt) == storedHash ? .same : .otherMac
    }

    /// The SHA-256 of the salt followed by the hardware UUID, as 64 lower-case hexadecimal
    /// characters.
    static func hardwareHash(of hardwareID: String, salt: Data) -> String {
        SHA256.hash(data: salt + Data(hardwareID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A new random salt of 32 bytes.
    static func makeSalt() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
}
