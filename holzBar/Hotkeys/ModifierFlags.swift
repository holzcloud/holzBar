//
//  ModifierFlags.swift
//  holzBar
//

import Carbon.HIToolbox
import Cocoa

/// Conversions between ``Modifiers`` and the system's modifier flags (Cocoa,
/// CoreGraphics and Carbon).
///
/// The type itself lives in `holzBar/Core/Modifiers.swift`, without AppKit or Carbon,
/// so that it can be unit tested.
extension Modifiers {
    /// Cocoa flags.
    var nsEventFlags: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if contains(.control) {
            result.insert(.control)
        }
        if contains(.option) {
            result.insert(.option)
        }
        if contains(.shift) {
            result.insert(.shift)
        }
        if contains(.command) {
            result.insert(.command)
        }
        return result
    }

    /// CoreGraphics flags.
    var cgEventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if contains(.control) {
            result.insert(.maskControl)
        }
        if contains(.option) {
            result.insert(.maskAlternate)
        }
        if contains(.shift) {
            result.insert(.maskShift)
        }
        if contains(.command) {
            result.insert(.maskCommand)
        }
        return result
    }

    /// Raw Carbon flags.
    var carbonFlags: Int {
        var result = 0
        if contains(.control) {
            result |= controlKey
        }
        if contains(.option) {
            result |= optionKey
        }
        if contains(.shift) {
            result |= shiftKey
        }
        if contains(.command) {
            result |= cmdKey
        }
        return result
    }

    /// Creates modifiers from Cocoa flags.
    init(nsEventFlags:NSEvent.ModifierFlags) {
        self.init()
        if nsEventFlags.contains(.control) {
            insert(.control)
        }
        if nsEventFlags.contains(.option) {
            insert(.option)
        }
        if nsEventFlags.contains(.shift) {
            insert(.shift)
        }
        if nsEventFlags.contains(.command) {
            insert(.command)
        }
    }

    /// Creates modifiers from CoreGraphics flags.
    init(cgEventFlags:CGEventFlags) {
        self.init()
        if cgEventFlags.contains(.maskControl) {
            insert(.control)
        }
        if cgEventFlags.contains(.maskAlternate) {
            insert(.option)
        }
        if cgEventFlags.contains(.maskShift) {
            insert(.shift)
        }
        if cgEventFlags.contains(.maskCommand) {
            insert(.command)
        }
    }

    /// Creates modifiers from raw Carbon flags.
    init(carbonFlags:Int) {
        self.init()
        if carbonFlags & controlKey == controlKey {
            insert(.control)
        }
        if carbonFlags & optionKey == optionKey {
            insert(.option)
        }
        if carbonFlags & shiftKey == shiftKey {
            insert(.shift)
        }
        if carbonFlags & cmdKey == cmdKey {
            insert(.command)
        }
    }
}
