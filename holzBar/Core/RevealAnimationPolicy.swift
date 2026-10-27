//
//  RevealAnimationPolicy.swift
//  holzBar
//

import Foundation

/// Decides whether a section divider's length steps when a section shows or hides.
///
/// The inputs are read at the moment of use: the setting "Animate showing and hiding", the
/// system's Reduce Motion flag, the macOS backend and whether the user is dragging an item.
/// Nothing is cached, nothing observes anything and no timer runs while idle.
///
/// The holzBar Shelf has its own, simpler rule (`ShelfAnimation`). macOS 27 has no divider
/// length and animates the bar itself.
nonisolated enum RevealAnimationPolicy {
    /// Whether the divider's length can step on the given backend.
    ///
    /// Only macOS 26 (`MenuBarBackendKind.service26`): macOS 14 and 15 keep the instant
    /// reveal until the stepping has been seen there, and macOS 27 has no divider length.
    static func supportsDividerSteps(_ backend: MenuBarBackendKind) -> Bool {
        backend == .service26
    }

    /// Whether a reveal or a hide steps the divider's length now.
    ///
    /// Reduce Motion always wins, and so does a drag: items must not slide under the pointer.
    static func stepsDivider(
        isEnabled: Bool,
        reduceMotion: Bool,
        backend: MenuBarBackendKind,
        isDraggingItem: Bool
    ) -> Bool {
        isEnabled && !reduceMotion && !isDraggingItem && supportsDividerSteps(backend)
    }
}
