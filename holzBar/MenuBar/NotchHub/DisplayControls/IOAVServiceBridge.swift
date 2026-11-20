//
//  IOAVServiceBridge.swift
//  holzBar
//

import Foundation
import IOKit

/// The one file of the app that names the undocumented functions `IOAVServiceCreateWithService`,
/// `IOAVServiceReadI2C` and `IOAVServiceWriteI2C`.
///
/// This is private API: Apple does not document it and may change it with any macOS update. It
/// is here because macOS has no public DDC/CI path on Apple silicon, and the maintainer agreed to
/// it for the Display controls module's switch External monitors (DDC) only (decisions of
/// 2026-11-05 and 2026-11-14), as a named exception under "Private API in modules" in
/// `CLAUDE.md`. What protects the app:
/// - The functions are looked up with `dlsym` on the default handle the first time they are
///   needed, never at launch and never through a link, so the app starts and runs when a
///   symbol is gone or changed. Nothing here runs while the module's switch is off, because the
///   caller never reaches this file then.
/// - A function is called only when all three were found; one missing symbol means none is
///   used (``resolve()`` answers `nil`).
/// - The registry is walked with public IOKit calls only; the display's name and its EDID are
///   never read.
/// - Every failure is a `nil` or `false`; the bus above counts them and ``PrivateFeatureGate``
///   switches the part off by itself.
///
/// The file keeps no observer, starts no timer, logs nothing and never uses the network. It is
/// not main-actor isolated: a transfer blocks for tens of milliseconds and runs on the queue of
/// ``DDCBus`` only.
nonisolated enum IOAVServiceBridge {
    /// `IOAVServiceCreateWithService(allocator, service)`; follows the Create rule.
    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?

    /// `IOAVServiceReadI2C(service, chipAddress, offset, buffer, size)`; 0 on success.
    typealias ReadI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    /// `IOAVServiceWriteI2C(service, chipAddress, dataAddress, buffer, size)`; 0 on success.
    typealias WriteI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    /// The three functions, found together.
    nonisolated struct Functions {
        let create: CreateWithService
        let read: ReadI2C
        let write: WriteI2C
    }

    /// The DDC channel of one external monitor: its service, chip address and the numbers of its
    /// framebuffer. It holds a non-Sendable service and never leaves ``DDCBus``.
    nonisolated final class Endpoint {
        /// The service created for the monitor's channel.
        let service: CFTypeRef
        /// The I2C chip address to talk to.
        let chip: UInt32
        /// The vendor, product and serial numbers of the monitor behind the channel.
        let framebuffer: DDCDisplayMatch.Framebuffer

        init(service: CFTypeRef, chip: UInt32, framebuffer: DDCDisplayMatch.Framebuffer) {
            self.service = service
            self.chip = chip
            self.framebuffer = framebuffer
        }
    }

    /// Looks the three functions up on the default handle, or `nil` when any is missing. Nothing
    /// is bit-cast before all three were found.
    static func resolve() -> Functions? {
        #if arch(arm64)
        // RTLD_DEFAULT, which Swift does not import.
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard
            let create = dlsym(defaultHandle, "IOAVServiceCreateWithService"),
            let read = dlsym(defaultHandle, "IOAVServiceReadI2C"),
            let write = dlsym(defaultHandle, "IOAVServiceWriteI2C")
        else {
            return nil
        }
        return Functions(
            create: unsafeBitCast(create, to: CreateWithService.self),
            read: unsafeBitCast(read, to: ReadI2C.self),
            write: unsafeBitCast(write, to: WriteI2C.self)
        )
        #else
        return nil
        #endif
    }

    /// The channel of every external monitor, in one walk of the IOService plane.
    ///
    /// The walk remembers the last framebuffer it passed and reads the monitor's vendor, product
    /// and serial numbers from it; at each external display-service proxy it creates the service
    /// once and pairs it with those numbers. A proxy without a framebuffer before it, or one
    /// whose framebuffer has no numbers, is skipped. Every registry object is released.
    static func endpoints(using functions: Functions) -> [Endpoint] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else {
            return []
        }
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        let options = IOOptionBits(kIORegistryIterateRecursively)
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, options, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var endpoints = [Endpoint]()
        var framebuffer: DDCDisplayMatch.Framebuffer?
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else {
                break
            }
            defer { IOObjectRelease(entry) }
            if IOObjectConformsTo(entry, "AppleCLCD2") != 0 || IOObjectConformsTo(entry, "IOMobileFramebufferShim") != 0 {
                // A framebuffer without numbers (the built-in one) clears the memory, so the
                // proxy behind it cannot take a monitor's numbers from an earlier one.
                framebuffer = numbers(of: entry)
            } else if
                IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0,
                let framebuffer,
                property(of: entry, "Location") as? String == "External",
                let service = functions.create(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                endpoints.append(Endpoint(service: service, chip: chipAddress(of: entry), framebuffer: framebuffer))
            }
        }
        return endpoints
    }

    /// Writes a request and reads the reply that follows it: the request is written
    /// ``DDCTiming/writeCycles`` times, ``DDCTiming/writeWait`` apart, then the reply is read
    /// after ``DDCTiming/readWait``. Returns the bytes read, or `nil` when a transfer fails. The
    /// bytes are not trusted; ``DDCReply`` checks them, and the bus decides about retries.
    static func transfer(_ request: [UInt8], replyLength: Int, endpoint: Endpoint, functions: Functions) -> [UInt8]? {
        guard replyLength > 0, write(request, to: endpoint, using: functions) else {
            return nil
        }
        usleep(DDCTiming.readWait)
        var reply = [UInt8](repeating: 0, count: replyLength)
        guard functions.read(endpoint.service, endpoint.chip, 0, &reply, UInt32(reply.count)) == 0 else {
            return nil
        }
        return reply
    }

    /// Writes a request that has no reply, such as a Set VCP: only the write cycles of
    /// ``transfer(_:replyLength:endpoint:functions:)``. Returns `false` when a write fails.
    static func send(_ request: [UInt8], endpoint: Endpoint, functions: Functions) -> Bool {
        write(request, to: endpoint, using: functions)
    }

    private static func write(_ request: [UInt8], to endpoint: Endpoint, using functions: Functions) -> Bool {
        var frame = request
        for _ in 0..<DDCTiming.writeCycles {
            usleep(DDCTiming.writeWait)
            guard functions.write(endpoint.service, endpoint.chip, DDCPacket.dataAddress, &frame, UInt32(frame.count)) == 0 else {
                return false
            }
        }
        return true
    }

    /// The chip address of a proxy: the one of Apple's MCDP display controllers when the
    /// proxy's parent says so, else the standard one.
    private static func chipAddress(of proxy: io_registry_entry_t) -> UInt32 {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) == KERN_SUCCESS else {
            return DDCPacket.standardChipAddress
        }
        defer { IOObjectRelease(parent) }
        let provider = property(of: parent, "EPICProviderClass") as? String
        return provider == "AppleDCPMCDP29XX" ? DDCPacket.mcdpChipAddress : DDCPacket.standardChipAddress
    }

    /// The vendor, product and serial numbers a framebuffer reports for its monitor, or `nil`
    /// when it has none.
    private static func numbers(of framebuffer: io_registry_entry_t) -> DDCDisplayMatch.Framebuffer? {
        guard
            let attributes = property(of: framebuffer, "DisplayAttributes") as? [String: Any],
            let product = attributes["ProductAttributes"] as? [String: Any],
            let vendor = number(product["LegacyManufacturerID"]),
            let model = number(product["ProductID"]),
            let serial = number(product["SerialNumber"])
        else {
            return nil
        }
        return DDCDisplayMatch.Framebuffer(vendor: vendor, product: model, serial: serial)
    }

    /// A registry number as the unsigned 32-bit value display numbers are. A negative number
    /// that fits 32 bits is read as the same bits.
    private static func number(_ value: Any?) -> UInt32? {
        guard let number = value as? NSNumber else {
            return nil
        }
        let wide = number.int64Value
        if let exact = UInt32(exactly: wide) {
            return exact
        }
        return Int32(exactly: wide).map { UInt32(bitPattern: $0) }
    }

    private static func property(of entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
