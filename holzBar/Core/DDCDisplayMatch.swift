//
//  DDCDisplayMatch.swift
//  holzBar
//

import Foundation

/// Pairs the displays macOS lists with the framebuffers whose DDC channel can reach them, and
/// pairs only where the pairing cannot be wrong.
///
/// A display is known by its vendor, model and serial number, the same three numbers a
/// framebuffer reports. Identical monitors, which share all three (a serial of 0 is common), are
/// told apart by nothing, so none of them is paired: holzBar never risks changing the wrong
/// monitor.
nonisolated enum DDCDisplayMatch {
    /// A display as macOS lists it.
    struct Display: Equatable, Sendable {
        /// The display's identifier.
        let id: UInt32
        /// The vendor number.
        let vendor: UInt32
        /// The model number.
        let model: UInt32
        /// The serial number, 0 when the monitor has none.
        let serial: UInt32
        /// Whether this is the built-in display, which has no DDC channel and is never paired.
        let isBuiltIn: Bool
    }

    /// A framebuffer with the numbers of the monitor it drives.
    struct Framebuffer: Equatable, Sendable {
        /// The vendor number.
        let vendor: UInt32
        /// The product (model) number.
        let product: UInt32
        /// The serial number, 0 when the monitor has none.
        let serial: UInt32
    }

    /// The outcome of a pairing.
    struct Result: Equatable, Sendable {
        /// For each paired display, the index of its framebuffer.
        let pairs: [UInt32: Int]
        /// The displays that fit more than one framebuffer, or share a framebuffer with another
        /// display. They are never written.
        let indistinguishable: Set<UInt32>
    }

    /// Pairs displays with framebuffers. A display is paired with a framebuffer only when that
    /// is the only framebuffer with its three numbers and the display is the only external
    /// display with the framebuffer's numbers. A display that fits no framebuffer is neither
    /// paired nor indistinguishable.
    static func match(displays: [Display], framebuffers: [Framebuffer]) -> Result {
        let externals = displays.filter { !$0.isBuiltIn }
        var pairs = [UInt32: Int]()
        var ties = Set<UInt32>()
        for display in externals {
            let candidates = framebuffers.indices.filter { fits(display, framebuffers[$0]) }
            guard let index = candidates.first else {
                continue
            }
            let rivals = externals.filter { fits($0, framebuffers[index]) }
            if candidates.count == 1, rivals.count == 1 {
                pairs[display.id] = index
            } else {
                ties.insert(display.id)
            }
        }
        return Result(pairs: pairs, indistinguishable: ties)
    }

    private static func fits(_ display: Display, _ framebuffer: Framebuffer) -> Bool {
        display.vendor == framebuffer.vendor
            && display.model == framebuffer.product
            && display.serial == framebuffer.serial
    }
}
