//
//  ConcealmentPlanner27.swift
//  holzBar
//

import Foundation

/// How much of holzBar's hidden content is currently revealed.
nonisolated enum RevealState27: Equatable {
    case allHidden
    case hiddenRevealed
    case allRevealed
}

nonisolated extension RevealState27 {
    /// The state the concealment follows, from the sections' own states.
    ///
    /// Whether a reveal goes to the holzBar Shelf or to the bar is chosen once, when a section
    /// is shown (`MenuBarSection.show`): a reveal on the bar sets the section's control item to
    /// show it, a reveal in the Shelf leaves it hiding. Asking at update time whether the Shelf
    /// is used read the pointer's display, so the bar flipped between concealed and revealed as
    /// the pointer crossed displays with the Shelf limited to some of them (D-11).
    ///
    /// - Parameters:
    ///   - layoutPaneOpen: Whether Menu Bar Layout is open, which draws every item.
    ///   - hiddenShownOnBar: Whether the hidden section's control item shows it on the bar.
    ///   - alwaysHiddenShownOnBar: Whether the always-hidden section's control item shows it.
    ///   - alwaysHiddenEnabled: Whether the always-hidden section is on.
    static func decide(
        layoutPaneOpen: Bool,
        hiddenShownOnBar: Bool,
        alwaysHiddenShownOnBar: Bool,
        alwaysHiddenEnabled: Bool
    ) -> RevealState27 {
        if layoutPaneOpen {
            return .allRevealed
        }
        if alwaysHiddenEnabled, alwaysHiddenShownOnBar {
            return .allRevealed
        }
        if hiddenShownOnBar {
            return .hiddenRevealed
        }
        return .allHidden
    }
}

/// Turns a layout and a reveal state into assessment-mode assertions.
///
/// Measured on macOS 27.0: live assertions combine as a union of their
/// allowlists, so an item shows if any assertion allows it. One assertion per
/// state is therefore enough, and a state that conceals nothing needs none —
/// which matters, because any live assertion also stops clicks on the clock.
nonisolated enum ConcealmentPlanner27 {
    /// The concealed bundle sets, one per assertion, that produce the given state.
    static func concealedSets(layout: [String: MacOS27Section], state: RevealState27) -> [Set<String>] {
        switch state {
        case .allHidden:
            let concealed = SectionLayout27.bundles(in: [.hidden, .alwaysHidden], layout: layout)
            return concealed.isEmpty ? [] : [concealed]
        case .hiddenRevealed:
            let concealed = SectionLayout27.bundles(in: [.alwaysHidden], layout: layout)
            return concealed.isEmpty ? [] : [concealed]
        case .allRevealed:
            return []
        }
    }

    /// The concealed sets for the given state, with the temporarily shown applications
    /// allowed in every assertion: an item that is clicked or photographed appears for a moment.
    static func concealedSets(layout: [String: MacOS27Section], state: RevealState27, temporarilyShown: Set<String>) -> [Set<String>] {
        concealedSets(layout: layout, state: state).compactMap { concealed in
            let remaining = concealed.subtracting(temporarilyShown)
            return remaining.isEmpty ? nil : remaining
        }
    }

    /// The allowlist an assertion needs to conceal exactly the given applications.
    static func allowlist(concealing concealed: Set<String>, running: Set<String>) -> [String] {
        running.subtracting(concealed).sorted()
    }

    /// The numbers of MenuBarAgent's system items an assertion keeps on the bar while it
    /// conceals the given set. A hidden system item is an entry of the set (``SystemItems27``).
    static func allowedSystemItems(concealing concealed: Set<String>) -> [Int] {
        SystemItems27.allowedNumbers(concealing: concealed)
    }

    /// The applications concealed while all of the given sets are live.
    static func effectivelyConcealed(sets: [Set<String>]) -> Set<String> {
        guard let first = sets.first else {
            return []
        }
        return sets.dropFirst().reduce(first) { $0.intersection($1) }
    }
}
