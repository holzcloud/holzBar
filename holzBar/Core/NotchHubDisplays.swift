//
//  NotchHubDisplays.swift
//  holzBar
//

import Foundation

/// The displays the Notch hub may open on.
///
/// The raw values are stored in the settings; new cases go at the end.
nonisolated enum NotchHubDisplays: Int, CaseIterable, Sendable {
    /// Every display: at the notch where there is one, hanging from the top centre elsewhere.
    case all = 0

    /// The built-in display only.
    case builtIn = 1

    /// Displays with a camera cutout only: a notch, or Apple's Dynamic Island (decision D-17 of
    /// Phase 93). Callers pass `safeAreaInsets.top != 0` as `hasNotch`, which is true for both.
    case notched = 2

    /// Every display, and the one the pointer is on decides where the hub opens (decision D-11 of
    /// Phase 96): the hotkey, an alert click, the live state and the indicators go to the display
    /// under the pointer, else to the one of the key window, else to the first. The hover zones
    /// exist on every display. Appended as raw value 3; the stored values never change meaning.
    case followPointer = 3

    /// Whether the hub may open on a display.
    ///
    /// - Parameters:
    ///   - isBuiltIn: Whether the display is the Mac's built-in one.
    ///   - hasNotch: Whether the display has any camera cutout, Apple's Dynamic Island included.
    func includes(isBuiltIn: Bool, hasNotch: Bool) -> Bool {
        switch self {
        case .all, .followPointer: true
        case .builtIn: isBuiltIn
        case .notched: hasNotch
        }
    }

    /// Whether, with the pointer on no included display, the display of the key window is the
    /// next choice before the first included one. Only Follow the pointer does this; the other
    /// rules keep their older behaviour (the pointer's display if it is included, else the first).
    var fallsBackToKeyWindow: Bool {
        self == .followPointer
    }

    /// The display the hub opens on, out of the ones this rule includes.
    ///
    /// The pointer's display when it is in `included`; else, for a rule that falls back to the key
    /// window (``fallsBackToKeyWindow``), the key window's display when it is in `included`; else
    /// the first included display. With no included display the answer is `nil` and the hub does
    /// not open. Nothing watches the pointer for this: the caller reads it when it asks.
    ///
    /// - Parameters:
    ///   - pointer: The display under the pointer, or `nil` when none is.
    ///   - keyWindow: The display of the key window, or `nil` when there is none.
    ///   - included: The displays the rule includes, in screen order.
    func preferred<ID: Equatable>(pointer: ID?, keyWindow: ID?, included: [ID]) -> ID? {
        if let pointer, included.contains(pointer) {
            return pointer
        }
        if fallsBackToKeyWindow, let keyWindow, included.contains(keyWindow) {
            return keyWindow
        }
        return included.first
    }
}
