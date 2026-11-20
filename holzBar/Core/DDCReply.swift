//
//  DDCReply.swift
//  holzBar
//

import Foundation

/// What a monitor's answer to a Get VCP request says, after every byte of it was checked.
///
/// A reply comes from monitor firmware over I2C and is not trusted: the buffer it was read into
/// may still hold the tail of an earlier reply, a monitor may answer for another code, and a
/// transfer can return noise. ``parse(_:expecting:)`` accepts a value only from a frame whose
/// length byte, address, checksum, opcode, length and echoed code are right.
nonisolated enum DDCReply: Equatable, Sendable {
    /// The monitor reported the control: the value now and the largest value it accepts.
    case value(current: UInt16, maximum: UInt16)

    /// The monitor does not support the control: it said so, or its range is empty.
    case unsupported

    /// The monitor had nothing to say yet (a message of length 0); the request may be repeated.
    case nullMessage

    /// The bytes are not a valid reply for the request.
    case invalid(Problem)

    /// Why a reply was rejected.
    enum Problem: Equatable, Sendable {
        /// Fewer than three bytes, so not even the length byte could be read.
        case tooShort
        /// The first byte is not the monitor's address 0x6E.
        case wrongAddress
        /// The length byte does not carry the DDC/CI flag 0x80.
        case wrongLengthByte
        /// The frame the length byte announces does not fit in the bytes read.
        case frameTooLong
        /// The checksum does not match the frame.
        case checksum
        /// The frame is not a Get VCP reply of the right length.
        case wrongOpcode
        /// The reply names another control than the one asked for.
        case wrongCode
        /// The result code is neither 0 (no error) nor 1 (unsupported).
        case resultCode
    }

    /// The address a monitor puts first in a reply.
    private static let monitorAddress: UInt8 = 0x6E

    /// The start of a reply's checksum: the source address 0x50 the monitor writes to.
    private static let checksumSeed: UInt8 = 0x50

    /// The opcode of a Get VCP reply.
    private static let replyOpcode: UInt8 = 0x02

    /// The length byte of a Get VCP reply: opcode, result, code, type and two 2-byte values.
    private static let replyLength = 8

    /// Reads a reply to a Get VCP request for `control`.
    ///
    /// The frame is found by its length byte, never by the size of the buffer: it is the first
    /// `length + 3` bytes, and whatever follows is never read.
    static func parse(_ bytes: [UInt8], expecting control: DDCControl) -> DDCReply {
        guard bytes.count >= 3 else {
            return .invalid(.tooShort)
        }
        guard bytes[0] == monitorAddress else {
            return .invalid(.wrongAddress)
        }
        guard bytes[1] & 0x80 != 0 else {
            return .invalid(.wrongLengthByte)
        }
        let length = Int(bytes[1] & 0x7F)
        let checksumIndex = length + 2
        guard checksumIndex < bytes.count else {
            return .invalid(.frameTooLong)
        }
        let expected = bytes[0..<checksumIndex].reduce(checksumSeed, ^)
        guard expected == bytes[checksumIndex] else {
            return .invalid(.checksum)
        }
        if length == 0 {
            return .nullMessage
        }
        guard bytes[2] == replyOpcode, length == replyLength else {
            return .invalid(.wrongOpcode)
        }
        guard bytes[4] == control.rawValue else {
            return .invalid(.wrongCode)
        }
        switch bytes[3] {
        case 0:
            let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
            let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
            return maximum == 0 ? .unsupported : .value(current: current, maximum: maximum)
        case 1:
            return .unsupported
        default:
            return .invalid(.resultCode)
        }
    }
}
