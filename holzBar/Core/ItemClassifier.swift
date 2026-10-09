//
//  ItemClassifier.swift
//  holzBar
//

import Foundation

/// A menu bar item as the clean-up assistant sees it: static facts only, nothing observed.
nonisolated struct ClassifiableItem: Equatable, Sendable {
    /// The item's identity key (`namespace:title`).
    var key: String
    /// The bundle identifier of the item's application.
    var namespace: String
    var title: String
    /// The application's `LSApplicationCategoryType`, when it has one.
    var applicationCategory: String?
    /// The section the item is in now: 0 visible, 1 hidden, 2 always hidden.
    var section: Int
}

/// What kind of item it is, for the clean-up assistant.
nonisolated enum ItemClass: Equatable, Sendable {
    /// The clock, battery, Wi-Fi, Control Center and sound: stay visible.
    case essential
    /// Reads something that changes (a time, a count, a load): the user reads it and does not
    /// click it, so it is not proposed for hiding.
    case information
    /// Something that works in the background and is rarely clicked: proposed for hiding.
    case setAndForget
    /// Mail, messages and calendars carry badges: stay visible.
    case communication
    /// Nothing is known: stays where it is.
    case unknown
}

/// Why the assistant proposes to hide an item.
nonisolated enum ProposalReason: Equatable, Sendable {
    /// A system extra of Control Center that is rarely needed on the bar.
    case systemExtra
    /// A utility or developer tool that works in the background.
    case backgroundTool
    /// A storage, backup or security helper that works in the background.
    case knownHelper
}

/// One item the assistant proposes to hide.
nonisolated struct CleanUpProposal: Equatable, Sendable {
    var item: ClassifiableItem
    var reason: ProposalReason
}

/// Sorts menu bar items into classes and proposes which to hide, from static facts: the
/// namespace, the application's category and a short table of known helpers. It is
/// conservative: it only proposes hiding visible items, never moves a hidden item into view,
/// and leaves the essentials, live values and everything it does not know alone.
nonisolated enum ItemClassifier {
    /// Categories of applications that work in the background.
    static let backgroundCategories: Set<String> = [
        "public.app-category.utilities",
        "public.app-category.developer-tools",
    ]

    /// Categories of applications whose items carry badges.
    static let communicationCategories: Set<String> = [
        "public.app-category.social-networking",
        "public.app-category.business",
    ]

    /// Control Center's items that are rarely needed on the bar, in lower case.
    static let systemExtraTitles: Set<String> = [
        "bluetooth", "focusmodes", "display", "nowplaying", "screenmirroring", "airplay",
        "siri", "spotlight", "userswitcher", "audiovideomodule", "accessibilityshortcuts",
    ]

    /// Applications known to work in the background, by bundle identifier.
    static let knownHelpers: Set<String> = [
        "com.getdropbox.dropbox",
        "com.microsoft.OneDrive",
        "com.google.drivefs",
        "com.backblaze.bzbmenu",
        "com.objective-see.lulu.app",
        "com.apple.TimeMachine",
    ]

    /// The class of an item.
    static func classify(_ item: ClassifiableItem) -> ItemClass {
        if PinnedSystemItems.isPinned(key: item.key) {
            return .essential
        }
        // A title that changes with a value: its canonical form differs from the title.
        if ItemIdentity.canonicalTitle(item.title) != item.title {
            return .information
        }
        if item.namespace == PinnedSystemItems.namespace {
            return systemExtraTitles.contains(item.title.lowercased()) ? .setAndForget : .unknown
        }
        if knownHelpers.contains(item.namespace) {
            return .setAndForget
        }
        if let category = item.applicationCategory {
            if communicationCategories.contains(category) {
                return .communication
            }
            if backgroundCategories.contains(category) {
                return .setAndForget
            }
        }
        return .unknown
    }

    /// The items to propose hiding: visible items of the class set-and-forget.
    static func proposals(for items: [ClassifiableItem]) -> [CleanUpProposal] {
        items.compactMap { item in
            guard item.section == 0, classify(item) == .setAndForget else {
                return nil
            }
            return CleanUpProposal(item: item, reason: reason(for: item))
        }
    }

    private static func reason(for item: ClassifiableItem) -> ProposalReason {
        if item.namespace == PinnedSystemItems.namespace {
            return .systemExtra
        }
        if knownHelpers.contains(item.namespace) {
            return .knownHelper
        }
        return .backgroundTool
    }
}
