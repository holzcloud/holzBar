//
//  RevealOwnership.swift
//  holzBar
//

import Foundation

/// Who showed the hidden sections, and what that show expanded.
///
/// One rule decides every automatic hide: what a trigger showed, that trigger may hide again.
/// Show on hover hides only a reveal that hover made; a section shown by a click, a hotkey, the
/// holzBar icon, the Shelf or any other way stays until the rehide strategy hides it. A user's
/// own request while a section is already shown (a click on an item, a hotkey) takes the reveal
/// over, so an automatic trigger no longer hides it.
///
/// The app records a show only where the sections really change (a section that is already
/// shown, or a show waiting for Touch ID, records nothing), and a hide with the sections it
/// collapsed.
nonisolated struct RevealOwnership: Equatable, Sendable {
    /// A menu bar section, as far as ownership is concerned.
    enum Section: Hashable, Sendable, CaseIterable {
        case visible
        case hidden
        case alwaysHidden
    }

    /// What showed the sections.
    enum Origin: Hashable, Sendable, CaseIterable {
        /// Show on hover.
        case hover
        /// A click: on holzBar's icon, on the empty menu bar, or on an item in the bar.
        case click
        /// A section hotkey.
        case hotkey
        /// The holzBar Shelf.
        case shelf
        /// "Show the hidden section for a moment".
        case peek
        /// "Show when it changes".
        case changeReveal
        /// A Command-drag in the menu bar.
        case drag
        /// The behaviour of the display under the pointer.
        case displayBehavior
        /// An automation rule.
        case rule
        /// Any other way (a URL command, a Shortcut, a menu).
        case other

        /// Whether holzBar showed the sections by itself rather than at the user's request.
        /// Only a user's request takes a reveal that is already shown over.
        var isAutomatic: Bool {
            switch self {
            case .hover, .changeReveal, .drag, .rule, .displayBehavior:
                true
            case .click, .hotkey, .shelf, .peek, .other:
                false
            }
        }
    }

    /// One show, or one takeover of a show; a later show or takeover makes it stale.
    struct Token: Hashable, Sendable {
        let generation: Int
        let origin: Origin
    }

    /// The current reveal, or `nil` when nothing holzBar recorded is shown.
    private(set) var current: Token?

    /// The sections the current reveal expanded (that were hidden before it).
    private(set) var expanded: Set<Section> = []

    /// Counts shows and takeovers, so every token is new.
    private var generation = 0

    /// Whether show on hover owns the current reveal and may hide it again.
    var hoverOwns: Bool {
        current?.origin == .hover
    }

    /// Records a show that expanded the given sections, and returns its token.
    @discardableResult
    mutating func didShow(_ origin: Origin, expanded sections: Set<Section>) -> Token {
        generation += 1
        let token = Token(generation: generation, origin: origin)
        current = token
        expanded = sections
        return token
    }

    /// Makes the current reveal the given origin's (a user's request while the sections are
    /// already shown). Keeps what the reveal expanded; earlier tokens become stale. Does nothing
    /// and returns `nil` when nothing is shown.
    @discardableResult
    mutating func takeOver(by origin: Origin) -> Token? {
        guard current != nil else {
            return nil
        }
        generation += 1
        let token = Token(generation: generation, origin: origin)
        current = token
        return token
    }

    /// Records that the given sections were hidden. When nothing of the reveal is left
    /// expanded, the reveal ends.
    mutating func didHide(_ sections: Set<Section>) {
        expanded.subtract(sections)
        if expanded.isEmpty {
            current = nil
        }
    }

    /// Whether the token belongs to the current reveal.
    func isCurrent(_ token: Token) -> Bool {
        token == current
    }

    /// The sections the token's trigger may hide: what its show expanded while it is still the
    /// current reveal, else nothing.
    func mayHide(_ token: Token) -> Set<Section> {
        isCurrent(token) ? expanded : []
    }

    /// The sections a rehide of the given section collapses: every section the current reveal
    /// expanded when the section is one of them (showing the always-hidden section also opened
    /// the hidden one), else the section alone (it keeps its own rehide).
    func sectionsToHide(rehiding section: Section) -> Set<Section> {
        expanded.contains(section) ? expanded : [section]
    }
}
