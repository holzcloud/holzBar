//
//  ItemCategoryTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("ItemCategory")
struct ItemCategoryTests {
    private let prefix = "public.app-category."

    /// An item with the facts the classifier looks at.
    private func item(
        _ namespace: String,
        title: String = "Item",
        category: String? = nil,
        own: Bool = false
    ) -> ClassifiableItem {
        ClassifiableItem(
            key: "\(namespace):\(title)",
            namespace: namespace,
            title: title,
            applicationCategory: category.map { prefix + $0 },
            section: 0,
            isOwnItem: own
        )
    }

    private func category(
        _ namespace: String,
        title: String = "Item",
        category: String? = nil,
        own: Bool = false
    ) -> ItemCategory {
        ItemCategoryClassifier.category(of: item(namespace, title: title, category: category, own: own))
    }

    @Test("The cases come in this order, each with a symbol and a title")
    func cases() {
        #expect(ItemCategory.allCases == [
            .system, .network, .media, .communication, .productivity, .developer, .storage, .utilities, .other,
        ])
        #expect(ItemCategory.allCases.map { $0.symbolName } == [
            "gearshape", "wifi", "speaker.wave.2", "bubble.left.and.bubble.right", "checklist",
            "hammer", "externaldrive", "wrench.and.screwdriver", "ellipsis.circle",
        ])
        #expect(ItemCategory.allCases.map { $0.titleKey } == [
            "System", "Network", "Media", "Communication", "Productivity",
            "Developer", "Cloud and Backup", "Utilities", "Other",
        ])
        #expect(Set(ItemCategory.allCases.map { $0.titleKey }).count == ItemCategory.allCases.count)
    }

    @Test("holzBar's own item is other, whatever its category")
    func ownItem() {
        #expect(category("com.holzcloud.holzBar", category: "utilities", own: true) == .other)
        #expect(category("com.apple.controlcenter", title: "WiFi", own: true) == .other)
    }

    @Test("Known helpers: the firewall is network, the others are storage, also as utilities")
    func knownHelpers() {
        #expect(category("com.objective-see.lulu.app", category: "utilities") == .network)
        for namespace in ["com.getdropbox.dropbox", "com.microsoft.OneDrive", "com.google.drivefs", "com.backblaze.bzbmenu", "com.apple.TimeMachine"] {
            #expect(category(namespace, category: "utilities") == .storage)
        }
    }

    @Test("Control Center's titles: network, media or system, in any case")
    func controlCenterTitles() {
        let namespace = "com.apple.controlcenter"
        #expect(category(namespace, title: "WiFi") == .network)
        #expect(category(namespace, title: "VPN") == .network)
        for title in ["Sound", "NowPlaying", "AirPlay", "ScreenMirroring"] {
            #expect(category(namespace, title: title) == .media)
        }
        for title in ["Battery", "Clock", "Bluetooth", "FocusModes", "Display", "SomethingNew"] {
            #expect(category(namespace, title: title) == .system)
        }
    }

    @Test("Other Apple items: media for a media application, else system")
    func appleItems() {
        #expect(category("com.apple.Music", category: "music") == .media)
        #expect(category("com.apple.TV", category: "video") == .media)
        #expect(category("com.apple.Calendar", category: "productivity") == .system)
        #expect(category("com.apple.Spotlight") == .system)
        #expect(category("com.apple.Terminal", category: "utilities") == .system)
    }

    @Test("Name hints decide before the application's category")
    func nameHints() {
        #expect(category("com.example.vpn.helper", category: "utilities") == .network)
        #expect(category("com.acme.WireGuard") == .network)
        #expect(category("io.tailscale.ipn.macsys") == .network)
        #expect(category("com.spotify.client") == .media)
        #expect(category("com.tinyspeck.slackmacgap") == .communication)
        #expect(category("us.zoom.xos") == .communication)
        #expect(category("com.hnc.Discord") == .communication)
        #expect(category("com.microsoft.teams2") == .communication)
    }

    @Test("A name that merely resembles a hint is not matched")
    func namesThatMerelyResemble() {
        #expect(category("com.example.proxima") == .other)
        #expect(category("com.example.sketchbook") == .other)
    }

    @Test("The application's category: media, communication, productivity, developer, utilities")
    func applicationCategories() {
        for declared in ["music", "video", "entertainment", "photography", "graphics-design"] {
            #expect(category("com.example.app", category: declared) == .media)
        }
        for declared in ["social-networking", "business"] {
            #expect(category("com.example.app", category: declared) == .communication)
        }
        for declared in ["productivity", "education", "reference", "finance", "books"] {
            #expect(category("com.example.app", category: declared) == .productivity)
        }
        #expect(category("com.example.app", category: "developer-tools") == .developer)
        #expect(category("com.example.app", category: "utilities") == .utilities)
    }

    @Test("Games, news, travel, health, an unknown string and no category are other")
    func otherCategories() {
        for declared in ["games", "news", "travel", "healthcare-fitness", "board-games", "something-new"] {
            #expect(category("com.example.app", category: declared) == .other)
        }
        #expect(category("com.example.app") == .other)
        #expect(ItemCategoryClassifier.category(of: ClassifiableItem(
            key: "a:b", namespace: "a", title: "b", applicationCategory: "not-a-category", section: 1
        )) == .other)
    }

    @Test("Precedence: a hint beats the category, a known helper beats a hint, an own item beats all")
    func precedence() {
        #expect(category("com.example.vpn.client", category: "productivity") == .network)
        #expect(category("com.objective-see.lulu.app", category: "business") == .network)
        #expect(category("com.getdropbox.dropbox", category: "social-networking") == .storage)
        #expect(category("com.example.vpn", own: true) == .other)
    }

    @Test("The chips list each category once, in the case order")
    func chips() {
        #expect(ItemCategoryChips.chips(present: []).isEmpty)
        #expect(ItemCategoryChips.chips(present: [.other, .network, .other, .system, .network]) == [.system, .network, .other])
        #expect(ItemCategoryChips.chips(present: ItemCategory.allCases.reversed()) == ItemCategory.allCases)
    }

    @Test("The cycle goes All, then the present categories in order, and wraps forward")
    func cycleForward() {
        let present: [ItemCategory] = [.media, .network]
        #expect(ItemCategoryChips.next(after: nil, among: present, forward: true) == .network)
        #expect(ItemCategoryChips.next(after: .network, among: present, forward: true) == .media)
        #expect(ItemCategoryChips.next(after: .media, among: present, forward: true) == nil)
    }

    @Test("The cycle wraps backward from All to the last chip")
    func cycleBackward() {
        let present: [ItemCategory] = [.network, .media]
        #expect(ItemCategoryChips.next(after: nil, among: present, forward: false) == .media)
        #expect(ItemCategoryChips.next(after: .media, among: present, forward: false) == .network)
        #expect(ItemCategoryChips.next(after: .network, among: present, forward: false) == nil)
    }

    @Test("A selection that is not present counts as All, and no category always gives All")
    func cycleEdges() {
        #expect(ItemCategoryChips.next(after: .developer, among: [.network, .media], forward: true) == .network)
        #expect(ItemCategoryChips.next(after: .developer, among: [.network, .media], forward: false) == .media)
        for forward in [true, false] {
            #expect(ItemCategoryChips.next(after: nil, among: [], forward: forward) == nil)
            #expect(ItemCategoryChips.next(after: .media, among: [], forward: forward) == nil)
        }
    }

    @Test("A repeated or unordered list gives the same cycle as its chips")
    func cycleIgnoresOrderAndRepeats() {
        let messy: [ItemCategory] = [.media, .network, .media, .network]
        var forward = [ItemCategory?]()
        var selected: ItemCategory?
        for _ in 0..<4 {
            selected = ItemCategoryChips.next(after: selected, among: messy, forward: true)
            forward.append(selected)
        }
        #expect(forward == [.network, .media, nil, .network])
    }
}
