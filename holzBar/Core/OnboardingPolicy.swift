//
//  OnboardingPolicy.swift
//  holzBar
//

import Foundation

/// The three steps of the onboarding, in order (D-36).
nonisolated enum OnboardingStep: Int, CaseIterable, Sendable {
    /// What holzBar does: Visible and Hidden.
    case whatHolzBarDoes
    /// How to show hidden items, and how to hide an item on this Mac.
    case showHiddenItems
    /// Arrange the menu bar: by hand in Layout, or from holzBar's suggestion.
    case arrange

    /// The step's number, counted from 1.
    var number: Int {
        rawValue + 1
    }

    /// The step after this one, or `nil` after the last.
    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    /// How many steps there are.
    static var count: Int {
        allCases.count
    }
}

/// When the onboarding opens by itself, and what its steps say on this Mac (D-20, D-36, D-37).
nonisolated enum OnboardingPolicy {
    /// How an item is hidden on this Mac.
    nonisolated enum HidingWay: Equatable, Sendable {
        /// Before macOS 27: ⌘ Command-drag it to the left of the holzBar icon.
        case commandDrag
        /// macOS 27 hides whole apps.
        case perApp
    }

    /// Whether the onboarding opens by itself: once, on a new install, never for someone who
    /// imported settings or already made a profile (D-20, D-37).
    static func opensByItself(isPending: Bool, hasImportedSettings: Bool, hasProfiles: Bool) -> Bool {
        isPending && !hasImportedSettings && !hasProfiles
    }

    /// Whether Continue in the Permissions window opens Settings; while the onboarding waits,
    /// the onboarding comes instead (D-20).
    static func continueOpensSettings(isPending: Bool, hasImportedSettings: Bool) -> Bool {
        !isPending || hasImportedSettings
    }

    /// How an item is hidden on this Mac (D-36).
    static func hidingWay(isMacOS27: Bool) -> HidingWay {
        isMacOS27 ? .perApp : .commandDrag
    }

    /// Whether step 2 names the click on an empty spot and the scroll: only while both are on,
    /// so it is true for this Mac.
    static func mentionsClickAndScroll(showOnClick: Bool, showOnScroll: Bool) -> Bool {
        showOnClick && showOnScroll
    }
}

/// When Layout shows the tidy-up suggestion as one line, in place of the old alert (D-21).
nonisolated enum TidyUpSuggestionPolicy {
    /// The least number of visible items for which a suggestion is worth it.
    static let minimumVisibleItems = 6

    /// Whether the line shows: not answered yet, no imported settings, no profile, enough
    /// visible items and at least one proposal.
    static func showsLine(
        wasOffered: Bool,
        hasImportedSettings: Bool,
        hasProfiles: Bool,
        visibleItemCount: Int,
        proposalCount: Int
    ) -> Bool {
        !wasOffered
            && !hasImportedSettings
            && !hasProfiles
            && visibleItemCount >= minimumVisibleItems
            && proposalCount > 0
    }
}
