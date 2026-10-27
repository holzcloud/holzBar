//
//  RevealAnimationStyle.swift
//  holzBar
//

import Foundation

/// How showing and hiding the menu bar's items looks: the one choice behind "Animation".
///
/// The raw values are stored in the user's settings and in exported settings files; a new case
/// goes at the end and no value is ever reused.
///
/// What each style does depends on what holzBar draws itself:
///
/// - On macOS 26 the divider's length steps, so the items of the menu bar slide in and out.
///   Only ``smooth`` does that; an item of another app cannot fade, so ``fade`` and ``instant``
///   switch the items at once.
/// - The holzBar Shelf is holzBar's own window: ``smooth`` slides it out from under the menu bar
///   while it fades in, ``fade`` only fades it in and ``instant`` shows it at once.
/// - On macOS 27 the system animates the menu bar and holzBar has no hold on it, so the style
///   changes the Shelf only. On macOS 14 and 15 the items always appear at once.
///
/// Reduce Motion always wins: with it on, nothing animates whatever the style says.
nonisolated enum RevealAnimationStyle: Int, CaseIterable, Identifiable, Sendable {
    /// Nothing animates.
    case instant = 0
    /// The menu bar's items slide where the system lets holzBar do so, and the Shelf slides out
    /// from under the menu bar as it fades in.
    case smooth = 1
    /// The Shelf fades in; the menu bar's items change at once.
    case fade = 2

    var id: Int { rawValue }

    /// The style a user who never chose one gets. It matches what earlier versions did with
    /// both of their switches on.
    static let standard = RevealAnimationStyle.smooth

    /// The choice stored as `raw`, or the standard when the number names none: a settings file
    /// or an older or newer holzBar may have written anything.
    static func stored(_ raw: Int) -> RevealAnimationStyle {
        RevealAnimationStyle(rawValue: raw) ?? standard
    }

    /// The style that corresponds to the two switches earlier versions had ("Animate showing
    /// and hiding" for the menu bar, "Fade the holzBar Shelf in" for the Shelf). `nil` for a
    /// switch that was never set means its default, which was on.
    static func migrated(animatesShowHide: Bool?, animatesShelf: Bool?) -> RevealAnimationStyle {
        if animatesShowHide ?? true {
            return .smooth
        }
        return (animatesShelf ?? true) ? .fade : .instant
    }

    /// Whether the divider of a section steps its length (the items slide).
    var slidesBar: Bool {
        self == .smooth
    }
}

/// How the holzBar Shelf appears for a style, as plain numbers the panel plays once.
nonisolated enum ShelfAnimation {
    /// What the Shelf plays when it opens. Closing is never delayed.
    nonisolated struct Plan: Equatable, Sendable {
        /// How long the fade lasts, in seconds; 0 for none.
        var fadeDuration: TimeInterval
        /// How far, in points, the content starts above its place and slides down; 0 for none.
        var slideDistance: Double

        /// Whether the Shelf simply appears.
        var isInstant: Bool {
            fadeDuration <= 0 && slideDistance <= 0
        }

        static let instant = Plan(fadeDuration: 0, slideDistance: 0)
    }

    /// The longest a plan lasts, in seconds. Nothing runs before or after it.
    static let longestDuration: TimeInterval = 0.25

    /// The plan for a style: none with Reduce Motion on or for ``RevealAnimationStyle/instant``,
    /// a short fade for ``RevealAnimationStyle/fade`` and a slightly longer fade with a slide
    /// for ``RevealAnimationStyle/smooth``.
    static func plan(style: RevealAnimationStyle, reduceMotion: Bool) -> Plan {
        guard !reduceMotion else {
            return .instant
        }
        switch style {
        case .instant: return .instant
        case .fade: return Plan(fadeDuration: 0.15, slideDistance: 0)
        case .smooth: return Plan(fadeDuration: 0.22, slideDistance: 8)
        }
    }
}
