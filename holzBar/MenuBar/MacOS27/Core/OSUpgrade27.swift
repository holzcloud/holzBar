//
//  OSUpgrade27.swift
//  holzBar
//

import Foundation

/// What holzBar has to do at launch because macOS was updated since it last ran.
///
/// holzBar remembers the major macOS version it last ran on (`Defaults.Key.lastRunMacOSMajor`).
/// When the version it finds is another one, the stored state of the old generation has to be
/// carried over explicitly: before macOS 27 holzBar kept an item's section by identity
/// (`Defaults.Key.itemSections`), from macOS 27 it keeps one section per application
/// (`Defaults.Key.macOS27Layout`), so an upgrade must turn the first into the second.
nonisolated enum OSUpgrade27 {
    /// The steps an upgrade needs.
    struct Plan: Equatable {
        /// Seeds the macOS 27 layout again from the sections saved before macOS 27.
        var reseedsLayout = false
        /// Whether the stored version has to be written.
        var recordsVersion = false

        static let none = Plan()
    }

    /// Decides what a launch has to do.
    ///
    /// - Parameters:
    ///   - previousMajor: The macOS major version holzBar last ran on, `nil` before it recorded one
    ///     (an installation from before this was kept, which may already have been upgraded).
    ///   - currentMajor: The running macOS major version.
    ///   - layoutIsEmpty: Whether the macOS 27 layout holds no application.
    ///   - hasSavedSections: Whether sections saved before macOS 27 exist.
    static func plan(
        previousMajor: Int?,
        currentMajor: Int,
        layoutIsEmpty: Bool,
        hasSavedSections: Bool
    ) -> Plan {
        var plan = Plan()
        plan.recordsVersion = previousMajor != currentMajor
        // The sections of the old generation become the layout of the new one, unless the user
        // has arranged a layout of their own. This also repairs an installation that was
        // upgraded earlier and was left with an empty layout (it hides nothing).
        //
        // Only an update from before macOS 27, or from a version that was never recorded, does
        // this: from 27 on the layout is the record, and an empty one is the user's, so an update
        // from 27 to 28 must not bring back the stale sections of before 27. A dual boot that
        // goes 27, 26, 27 with a deliberately empty layout still reseeds on the way back to 27;
        // telling that apart would need another stored flag, which is not worth it.
        let isFromBefore27 = previousMajor.map { $0 < 27 } ?? true
        if currentMajor >= 27, layoutIsEmpty, hasSavedSections, previousMajor != currentMajor, isFromBefore27 {
            plan.reseedsLayout = true
        }
        return plan
    }
}
