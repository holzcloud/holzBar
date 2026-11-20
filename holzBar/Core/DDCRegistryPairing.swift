//
//  DDCRegistryPairing.swift
//  holzBar
//

import Foundation

/// Pairs each DDC proxy the registry walk found with the framebuffer that drives the same monitor,
/// by the relation the registry itself shows, and pairs only where the pairing cannot be wrong.
///
/// A framebuffer and its proxy sit in different branches of the registry, but both branches carry
/// the number of the external port in the name of an entry above them (`dispext0` above the
/// framebuffer, `dcpext0` and `dispext0:dcpav-service-epic:0` above the proxy). That number is
/// the slot. A proxy with a slot belongs to the one framebuffer with the same slot, and to none
/// when there is not exactly one. Only a proxy with no slot at all falls back to the framebuffer
/// the walk passed last. Whatever the route, a framebuffer that two proxies claim serves neither:
/// holzBar never risks writing to the wrong monitor. The value makes no registry call and holds no
/// names.
nonisolated enum DDCRegistryPairing {
    /// A proxy as the walk found it.
    struct Proxy: Equatable, Sendable {
        /// The slot named above the proxy, or `nil` when no entry above it names one.
        let slot: String?
        /// The index of the framebuffer the walk passed last before this proxy, if any.
        let previousFramebuffer: Int?
    }

    /// The slot a registry name carries: the first run of digits that follows `ext`, in either
    /// case, as `ext` and the number without leading zeros (`dispext0` gives `ext0`,
    /// `DCPEXT01Endpoint` gives `ext1`). `nil` when the name has none. A name such as
    /// `AFKEPInterfaceServiceKextV2` has `ext` but no digit right after it, so it has no slot.
    static func slot(in name: String) -> String? {
        let bytes = Array(name.utf8).map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
        let marker = Array("ext".utf8)
        var index = 0
        while index + marker.count < bytes.count {
            if bytes[index..<(index + marker.count)].elementsEqual(marker), isDigit(bytes[index + marker.count]) {
                var number = 0
                var cursor = index + marker.count
                while cursor < bytes.count, isDigit(bytes[cursor]), number < 1_000_000 {
                    number = number * 10 + Int(bytes[cursor] - 0x30)
                    cursor += 1
                }
                return "ext\(number)"
            }
            index += 1
        }
        return nil
    }

    /// For each proxy, the index of its framebuffer in `framebufferSlots` (the slot of each
    /// framebuffer the walk found, in walk order), or `nil` when it has none that is certain.
    static func pair(framebufferSlots: [String?], proxies: [Proxy]) -> [Int?] {
        let targets: [Int?] = proxies.map { proxy in
            guard let slot = proxy.slot else {
                return proxy.previousFramebuffer.flatMap { framebufferSlots.indices.contains($0) ? $0 : nil }
            }
            let matches = framebufferSlots.indices.filter { framebufferSlots[$0] == slot }
            return matches.count == 1 ? matches[0] : nil
        }
        var claims = [Int: Int]()
        for case let target? in targets {
            claims[target, default: 0] += 1
        }
        return targets.map { target in
            guard let target, claims[target] == 1 else {
                return nil
            }
            return target
        }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39
    }
}
