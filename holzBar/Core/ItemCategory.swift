//
//  ItemCategory.swift
//  holzBar
//

import Foundation

/// The kind of thing a menu bar item is, as a hint for browsing the search by category.
///
/// A category is worked out from static facts each time and never stored, so nothing about it
/// is persisted and the tables behind it can be refined in any release. A wrong category moves
/// and hides nothing.
nonisolated enum ItemCategory: CaseIterable, Sendable {
    case system
    case network
    case media
    case communication
    case productivity
    case developer
    /// Cloud storage, backup and file sync.
    case storage
    case utilities
    case other

    /// The name of the SF Symbol on the category's chip.
    var symbolName: String {
        switch self {
        case .system: "gearshape"
        case .network: "wifi"
        case .media: "speaker.wave.2"
        case .communication: "bubble.left.and.bubble.right"
        case .productivity: "checklist"
        case .developer: "hammer"
        case .storage: "externaldrive"
        case .utilities: "wrench.and.screwdriver"
        case .other: "ellipsis.circle"
        }
    }

    /// The English title, which is also its key in the string catalog.
    var titleKey: String {
        switch self {
        case .system: "System"
        case .network: "Network"
        case .media: "Media"
        case .communication: "Communication"
        case .productivity: "Productivity"
        case .developer: "Developer"
        case .storage: "Cloud and Backup"
        case .utilities: "Utilities"
        case .other: "Other"
        }
    }
}

/// Sorts a menu bar item into a category from the facts Phase 16's classifier already uses: the
/// namespace, the title, the application's declared category and short tables. It reuses that
/// classifier's tables instead of keeping a second copy.
///
/// The rules run in this order, and the first that applies decides:
/// 1. holzBar's own item is other.
/// 2. A known helper: the firewall is network, the other helpers are storage.
/// 3. Control Center's items by title: Wi-Fi and VPN are network; sound, now playing, AirPlay
///    and screen mirroring are media; every other title is system.
/// 4. Any other Apple namespace: media when the application's category is music, video,
///    entertainment or photography, else system.
/// 5. A name hint, a lower-case part of the namespace such as `vpn` or `spotify`.
/// 6. The application's declared category.
/// 7. Everything else, and an item whose application declares nothing, is other.
nonisolated enum ItemCategoryClassifier {
    /// The prefix of every category an application declares.
    private static let categoryPrefix = "public.app-category."

    /// The known helpers that are network tools; every other known helper is storage.
    static let networkHelpers: Set<String> = ["com.objective-see.lulu.app"]

    /// Control Center's titles for network items, in lower case.
    static let networkTitles: Set<String> = ["wifi", "vpn"]

    /// Control Center's titles for media items, in lower case.
    static let mediaTitles: Set<String> = ["sound", "nowplaying", "airplay", "screenmirroring"]

    /// The categories under which an Apple application is media.
    static let appleMediaCategories: Set<String> = declared(["music", "video", "entertainment", "photography"])

    /// Name hints, lower-case parts of a namespace, in the order they are tried.
    static let nameHints: [(part: String, category: ItemCategory)] = [
        ("vpn", .network), ("wireguard", .network), ("tailscale", .network),
        ("wifi", .network), ("proxy", .network), ("firewall", .network),
        ("spotify", .media),
        ("slack", .communication), ("zoom", .communication), ("discord", .communication), ("teams", .communication),
    ]

    /// What an application's declared category means, by the full declared string.
    static let applicationCategories: [String: ItemCategory] = {
        var table = [String: ItemCategory]()
        func add(_ names: [String], _ category: ItemCategory) {
            for name in names {
                table[categoryPrefix + name] = category
            }
        }
        add(["music", "video", "entertainment", "photography", "graphics-design"], .media)
        add(["productivity", "education", "reference", "finance", "books"], .productivity)
        add(["developer-tools"], .developer)
        add(["utilities"], .utilities)
        for declared in ItemClassifier.communicationCategories {
            table[declared] = .communication
        }
        return table
    }()

    /// The category of an item.
    static func category(of item: ClassifiableItem) -> ItemCategory {
        if item.isOwnItem {
            return .other
        }
        if ItemClassifier.knownHelpers.contains(item.namespace) {
            return networkHelpers.contains(item.namespace) ? .network : .storage
        }
        if item.namespace == PinnedSystemItems.namespace {
            return controlCenterCategory(title: item.title)
        }
        if item.namespace.hasPrefix("com.apple.") {
            if let declared = item.applicationCategory, appleMediaCategories.contains(declared) {
                return .media
            }
            return .system
        }
        let namespace = item.namespace.lowercased()
        for hint in nameHints where namespace.contains(hint.part) {
            return hint.category
        }
        if let declared = item.applicationCategory, let category = applicationCategories[declared] {
            return category
        }
        return .other
    }

    private static func controlCenterCategory(title: String) -> ItemCategory {
        let title = title.lowercased()
        if networkTitles.contains(title) {
            return .network
        }
        if mediaTitles.contains(title) {
            return .media
        }
        return .system
    }

    private static func declared(_ names: [String]) -> Set<String> {
        Set(names.map { categoryPrefix + $0 })
    }
}

/// The row of category chips in the search: which chips there are, and in what order.
nonisolated enum ItemCategoryChips {
    /// The chips for the categories the items fall into: each category once, in the order of
    /// ``ItemCategory``, whatever the order or repetition of the input. Empty for no category.
    static func chips(present categories: [ItemCategory]) -> [ItemCategory] {
        let present = Set(categories)
        return ItemCategory.allCases.filter { present.contains($0) }
    }

    /// The selection one step along the row, wrapping at the ends. The row is All (`nil`)
    /// followed by the chips of `present`; a selection that is not among them counts as All, and
    /// with no category present the result is always All.
    static func next(after selected: ItemCategory?, among present: [ItemCategory], forward: Bool) -> ItemCategory? {
        let row: [ItemCategory?] = [nil] + chips(present: present)
        let index = row.firstIndex { $0 == selected } ?? 0
        let step = forward ? 1 : row.count - 1
        return row[(index + step) % row.count]
    }
}
