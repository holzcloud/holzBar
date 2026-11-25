//
//  DDCPacket.swift
//  holzBar
//

import Foundation

/// The controls of an external monitor that holzBar reads and sets over DDC/CI, with their VCP
/// codes.
///
/// These four are the only codes a request can carry. The input source (code 0x60) has no case
/// here on purpose, so no request for it can be built anywhere in the app.
nonisolated enum DDCControl: UInt8, CaseIterable, Sendable {
    /// The backlight, VCP code 0x10.
    case brightness = 0x10
    /// The contrast, VCP code 0x12.
    case contrast = 0x12
    /// The speaker volume, VCP code 0x62.
    case volume = 0x62
    /// Mute, VCP code 0x8D: 1 mutes, 2 unmutes.
    case mute = 0x8D
}

/// Builds the DDC/CI request frames that are written to a monitor.
///
/// A frame is `[0x80 | (parameter count + 1), opcode, parameters..., checksum]`. The monitor's
/// address (0x6E) and the source address (0x51) are supplied by the I2C transfer, but both are
/// part of the checksum, which starts from `0x6E ^ 0x51` and takes in every byte before it.
nonisolated enum DDCPacket {
    /// The I2C chip address of a monitor's DDC/CI channel.
    static let standardChipAddress: UInt32 = 0x37

    /// The chip address on hardware whose display controller is an `AppleDCPMCDP29XX`.
    static let mcdpChipAddress: UInt32 = 0xB7

    /// The data address a request is written to; a reply is read from offset 0.
    static let dataAddress: UInt32 = 0x51

    /// The number of bytes read for a Get VCP reply: address, length, opcode, result, code,
    /// type, maximum (2), current (2) and checksum.
    static let getReplyLength = 11

    /// The number of bytes read for one fragment of the capabilities string: address, length,
    /// opcode, offset (2), at most 32 data bytes and checksum.
    static let capabilitiesReplyLength = 38

    /// The opcode of Get VCP Feature.
    private static let getOpcode: UInt8 = 0x01

    /// The opcode of Set VCP Feature.
    private static let setOpcode: UInt8 = 0x03

    /// The opcode of Get Capabilities.
    private static let capabilitiesOpcode: UInt8 = 0xF3

    /// The start of every checksum: the monitor's address 0x6E and the source address 0x51.
    private static let checksumSeed: UInt8 = 0x6E ^ 0x51

    /// The frame that asks a monitor for the current and the maximum value of a control.
    static func getRequest(_ control: DDCControl) -> [UInt8] {
        framed(opcode: getOpcode, parameters: [control.rawValue])
    }

    /// The frame that asks a monitor for the fragment of its capabilities string that starts at
    /// `offset`, sent big endian.
    static func capabilitiesRequest(offset: UInt16) -> [UInt8] {
        framed(opcode: capabilitiesOpcode, parameters: [UInt8(offset >> 8), UInt8(offset & 0xFF)])
    }

    /// The frame that sets a control to a raw value, sent big endian.
    static func setRequest(_ control: DDCControl, value: UInt16) -> [UInt8] {
        framed(opcode: setOpcode, parameters: [control.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func framed(opcode: UInt8, parameters: [UInt8]) -> [UInt8] {
        let body = [0x80 | UInt8(parameters.count + 1), opcode] + parameters
        return body + [body.reduce(checksumSeed, ^)]
    }
}

/// How long a DDC/CI transfer waits, as measured on a monitor that drops a request it hears
/// only once.
nonisolated enum DDCTiming {
    /// The wait before each write, in microseconds: 10 ms.
    static let writeWait: UInt32 = 10_000

    /// How often a request is written before the reply is read. Measured on a Samsung S34C65xV:
    /// it answered only after two writes, 10 ms apart each.
    static let writeCycles = 2

    /// The wait between the last write and the read, in microseconds: 50 ms, which the same
    /// monitor needed.
    static let readWait: UInt32 = 50_000

    /// How many transfers a read tries before it gives up (one and four retries).
    static let attempts = 5

    /// The wait before a retry, in microseconds: 20 ms.
    static let retryWait: UInt32 = 20_000

    /// How long after a change the value is read back, so a monitor that is still moving its
    /// backlight has settled: 0.3 s, an estimate to be tuned on real monitors.
    static let settle: Duration = .milliseconds(300)

    /// How long a first read lasts before its card shows a spinner: 150 ms, so a quick read
    /// never flashes one.
    static let readingIndicatorDelay: Duration = .milliseconds(150)

    /// How long after a wake or a display reconfiguration no transfer is sent: about 3 s,
    /// because monitors drop or garble requests while they come back (D-20). The wait counts
    /// from the event itself, not from the 2 s the menu bar needs to settle (``DDCWakeGate``).
    static let wakeWait: Duration = .seconds(3)
}
