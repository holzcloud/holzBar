import Testing
@testable import HolzBarCore

@Suite("ItemIdentity")
struct ItemIdentityTests {
    @Test("Numbers do not change an identity")
    func numbersDoNotChangeAnIdentity() {
        #expect(ItemIdentity.canonicalTitle("Mail 3") == ItemIdentity.canonicalTitle("Mail 12"))
        #expect(ItemIdentity.canonicalTitle("CPU 12%") == ItemIdentity.canonicalTitle("CPU 7%"))
        #expect(ItemIdentity.canonicalTitle("CPU 12%") != ItemIdentity.canonicalTitle("Network 3 KB/s"))
        #expect(ItemIdentity.canonicalTitle("Network 3 KB/s") == ItemIdentity.canonicalTitle("Network 1.5 MB/s"))
        // Identifiers keep their digits: they tell an app's items apart.
        #expect(ItemIdentity.canonicalTitle("Item-0") == "Item-0")
        #expect(ItemIdentity.canonicalTitle("Item-0") != ItemIdentity.canonicalTitle("Item-1"))
        #expect(ItemIdentity.canonicalTitle("com.apple.menuextra.clock") == "com.apple.menuextra.clock")
    }

    @Test("An app whose title changes is learned")
    func titleChangingAppIsLearned() {
        let holzBar = "com.holzcloud.holzBar"
        let uuid = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
        let previous: [ItemIdentity.Item] = [
            (namespace: "a", title: "Mon 3 Oct"),
            (namespace: "b", title: "Mail 3"),
            (namespace: "c", title: "One"),
            (namespace: "d", title: "Same"),
            (namespace: holzBar, title: "Old"),
            (namespace: uuid, title: "Old"),
        ]
        let current: [ItemIdentity.Item] = [
            (namespace: "a", title: "Tue 4 Oct"),
            (namespace: "b", title: "Mail 12"),
            (namespace: "c", title: "One"),
            (namespace: "c", title: "Two"),
            (namespace: "d", title: "Same"),
            (namespace: holzBar, title: "New"),
            (namespace: uuid, title: "New"),
        ]
        let learned = ItemIdentity.learnTitleChangingOwners(previous: previous, current: current, excluding: [holzBar])
        #expect(learned == ["a"])
    }

    @Test("Items of a learned app are keyed by position")
    func learnedAppKeyedByPosition() {
        let items: [ItemIdentity.Item] = [
            (namespace: "a", title: "Mon 3 Oct"),
            (namespace: "x", title: "Other"),
            (namespace: "a", title: "12:41"),
        ]
        let keys = ItemIdentity.keys(for: items, titleChangingOwners: ["a"])
        #expect(keys == ["a:#1", "x:Other", "a:#2"])
    }

    @Test("Several items of one app stay apart")
    func severalItemsOfOneAppStayApart() {
        let items: [ItemIdentity.Item] = [
            (namespace: "b", title: "Sync 3"),
            (namespace: "b", title: "Sync 5"),
            (namespace: "b", title: "Item-0"),
            (namespace: "b", title: "Item-1"),
        ]
        let keys = ItemIdentity.keys(for: items, titleChangingOwners: [])
        #expect(keys == ["b:Sync #", "b:Sync #:2", "b:Item-0", "b:Item-1"])
    }

    @Test("Stored keys from earlier versions still match")
    func storedKeysStillMatch() {
        let current = ItemIdentity.keys(for: [(namespace: "a", title: "Mail 12")], titleChangingOwners: [])
        #expect(ItemIdentity.storedKey("a:Mail 3", titleChangingOwners: []) == current[0])
        #expect(ItemIdentity.storedKey("a:anything", titleChangingOwners: ["a"]) == "a:#1")
        // Keys of this version are kept as they are.
        #expect(ItemIdentity.storedKey("a:#2", titleChangingOwners: ["a"]) == "a:#2")
        #expect(ItemIdentity.storedKey("b:Sync #:2", titleChangingOwners: []) == "b:Sync #:2")
        #expect(ItemIdentity.storedKey("b:Item-0", titleChangingOwners: []) == "b:Item-0")
        #expect(ItemIdentity.storedKey("b:Item-0:2", titleChangingOwners: []) == "b:Item-0:2")
        // A clock-like raw title matches the canonical one.
        let clock = ItemIdentity.keys(for: [(namespace: "c", title: "10:45")], titleChangingOwners: [])
        #expect(ItemIdentity.storedKey("c:10:42", titleChangingOwners: []) == clock[0])
    }

    @Test("Stored keys of untitled items match their current keys")
    func storedKeysOfUntitledItemsMatch() {
        let items: [ItemIdentity.Item] = [
            (namespace: "d", title: ""),
            (namespace: "d", title: ""),
            (namespace: "d", title: ""),
            (namespace: "e", title: ""),
        ]
        let keys = ItemIdentity.keys(for: items, titleChangingOwners: [])
        #expect(keys == ["d", "d:2", "d:3", "e"])
        for key in keys {
            #expect(ItemIdentity.storedKey(key, titleChangingOwners: []) == key)
        }
        #expect(ItemIdentity.storedKey("d:10", titleChangingOwners: []) == "d:10")
        // Occurrences start at 2 without a leading zero; other digits are earlier raw titles.
        #expect(ItemIdentity.storedKey("d:0", titleChangingOwners: []) == "d:#")
        #expect(ItemIdentity.storedKey("d:1", titleChangingOwners: []) == "d:#")
        #expect(ItemIdentity.storedKey("d:01", titleChangingOwners: []) == "d:#")
    }

    @Test("Stored values of stale keys never outrank the current key")
    func storedValuesPreferCurrentKey() {
        // The first run stored a canonical title; the app was later learned as title-changing.
        let stored = ["a:Mon # Oct": 1, "a:#1": 0, "a:Mail 3": 2, "b:Sync 3": 1, "b:Sync 5": 2]
        let values = ItemIdentity.storedValues(stored, titleChangingOwners: ["a"])
        #expect(values == ["a:#1": 0, "b:Sync #": 1])
        // Without the current key, the stale key that sorts first wins.
        let stale = ItemIdentity.storedValues(["a:Mon # Oct": 1, "a:Mail 3": 2], titleChangingOwners: ["a"])
        #expect(stale == ["a:#1": 2])
    }

    // MARK: First-line titles

    @Test("The identity of a multi-line title is its first line")
    func firstLineIsTheIdentity() {
        #expect(ItemIdentity.canonicalTitle("OneDrive - Personal\nSynced") == "OneDrive - Personal")
        #expect(ItemIdentity.canonicalTitle("OneDrive - Personal\nSyncing 3 files") == "OneDrive - Personal")
        #expect(ItemIdentity.canonicalTitle("OneDrive - Personal\r\nSynced") == "OneDrive - Personal")
        #expect(ItemIdentity.canonicalTitle("  OneDrive - Personal \nSynced") == "OneDrive - Personal")
        // The first line follows the number rule like any title.
        #expect(ItemIdentity.canonicalTitle("Mail 3\nUnread") == "Mail #")
        // A first line that is empty after trimming leaves the whole title to the existing rules.
        #expect(ItemIdentity.canonicalTitle("\nSynced 3") == "\nSynced #")
        #expect(ItemIdentity.canonicalTitle("  \nSynced") == "  \nSynced")
        // A single line is unchanged.
        #expect(ItemIdentity.canonicalTitle("OneDrive - Personal") == "OneDrive - Personal")
    }

    @Test("A multi-line title keeps one key and earlier stored keys still match")
    func firstLineKeysMatchStoredKeys() {
        let synced: [ItemIdentity.Item] = [(namespace: "ns", title: "OneDrive - Personal\nSynced")]
        let syncing: [ItemIdentity.Item] = [(namespace: "ns", title: "OneDrive - Personal\nSyncing 3 files")]
        let key = ItemIdentity.keys(for: synced, titleChangingOwners: [])
        #expect(key == ["ns:OneDrive - Personal"])
        #expect(ItemIdentity.keys(for: syncing, titleChangingOwners: []) == key)
        // A key of an earlier version holds the raw title with its second line.
        #expect(ItemIdentity.storedKey("ns:OneDrive - Personal\nSynced", titleChangingOwners: []) == "ns:OneDrive - Personal")
        #expect(ItemIdentity.storedKey("ns:OneDrive - Personal", titleChangingOwners: []) == "ns:OneDrive - Personal")
        // Such an app is not learned as title-changing.
        let learned = ItemIdentity.learnTitleChangingOwners(previous: synced, current: syncing, excluding: [])
        #expect(learned.isEmpty)
    }

    @Test("A stored multi-line key with an occurrence keeps its occurrence on the first line")
    func multiLineOccurrenceKeys() {
        #expect(ItemIdentity.storedKey("ns:A\nb:2", titleChangingOwners: []) == "ns:A:2")
        #expect(ItemIdentity.storedKey("ns:Status\nA:12", titleChangingOwners: []) == "ns:Status:12")
        // The current keys of the same two items.
        let items: [ItemIdentity.Item] = [(namespace: "ns", title: "Status\nA"), (namespace: "ns", title: "Status\nA")]
        #expect(ItemIdentity.keys(for: items, titleChangingOwners: []) == ["ns:Status", "ns:Status:2"])
        // Both stored sections survive the update apart.
        let values = ItemIdentity.storedValues(["ns:Status\nA": 1, "ns:Status\nA:2": 2], titleChangingOwners: [])
        #expect(values == ["ns:Status": 1, "ns:Status:2": 2])
        // A raw title of an earlier version that ends in a number is not an occurrence.
        #expect(ItemIdentity.storedKey("ns:Line1\nTime 10:12", titleChangingOwners: []) == "ns:Line1")
        #expect(ItemIdentity.storedKey("ns:Sync\nUp 3:2", titleChangingOwners: []) == "ns:Sync")
    }

    // MARK: Pinned Control Center controls

    private static let agent = "com.apple.MenuBarAgent"
    private static let screenshot = ":com.apple.screenshot.launcher:com.apple.controls.screenshot:com.apple.controls.screenshot.capture-custom"
    private static let uuidA = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    private static let uuidB = "0E984725-C51C-4BF4-9960-E1C80E27ABA0"

    @Test("A pinned control keeps one title whatever UUID macOS gives it")
    func pinnedControlIgnoresItsUUID() {
        let withA = ItemIdentity.canonicalTitle("\(Self.screenshot):\(Self.uuidA)")
        let withB = ItemIdentity.canonicalTitle("\(Self.screenshot):\(Self.uuidB)")
        #expect(withA == withB)
        #expect(withA == ItemIdentity.canonicalTitle(Self.screenshot))
        #expect(withA == Self.screenshot)
        // A digit inside the control's own name is not replaced.
        let timer = ":com.apple.timer2.launcher:com.apple.controls.timer2:com.apple.controls.timer2.start"
        #expect(ItemIdentity.canonicalTitle("\(timer):\(Self.uuidA)") == timer)
    }

    @Test("Two pinned controls of one kind get an occurrence number that survives storage")
    func pinnedControlKeysSurviveStorage() {
        let timer = ":com.apple.timer2.launcher:com.apple.controls.timer2:com.apple.controls.timer2.start"
        for control in [Self.screenshot, timer] {
            let items: [ItemIdentity.Item] = [
                (namespace: Self.agent, title: "\(control):\(Self.uuidA)"),
                (namespace: Self.agent, title: "\(control):\(Self.uuidB)"),
            ]
            let base = "\(Self.agent):\(control)"
            let keys = ItemIdentity.keys(for: items, titleChangingOwners: [])
            #expect(keys == [base, "\(base):2"])
            for key in keys {
                #expect(ItemIdentity.storedKey(key, titleChangingOwners: []) == key)
            }
            // A key stored with the instance UUID matches the current key.
            #expect(ItemIdentity.storedKey("\(base):\(Self.uuidA)", titleChangingOwners: []) == base)
        }
    }

    // MARK: Launch placeholders

    @Test("Item-N is a placeholder title")
    func placeholderTitles() {
        #expect(ItemIdentity.isPlaceholderTitle("Item-0"))
        #expect(ItemIdentity.isPlaceholderTitle("Item-12"))
        #expect(!ItemIdentity.isPlaceholderTitle("Item-"))
        #expect(!ItemIdentity.isPlaceholderTitle("item-0"))
        #expect(!ItemIdentity.isPlaceholderTitle("Item-0a"))
        #expect(!ItemIdentity.isPlaceholderTitle("OneDrive"))
        #expect(!ItemIdentity.isPlaceholderTitle(""))
    }

    @Test("A change to or from a placeholder is not a title-changing app")
    func placeholderChangeIsNotLearned() {
        func learned(_ previous: String, _ current: String) -> Set<String> {
            ItemIdentity.learnTitleChangingOwners(
                previous: [(namespace: "a", title: previous)],
                current: [(namespace: "a", title: current)],
                excluding: []
            )
        }
        #expect(learned("Item-0", "OneDrive").isEmpty)
        #expect(learned("OneDrive", "Item-0").isEmpty)
        #expect(learned("Item-1", "Item-0").isEmpty)
        // Real title changes are still learned.
        #expect(learned("Mon 3 Oct", "Tue 4 Oct").isEmpty == false)
        #expect(learned("One", "Two") == ["a"])
    }

    @Test("A placeholder change of one app does not hide the change of another")
    func placeholderRuleIsPerNamespace() {
        let previous: [ItemIdentity.Item] = [
            (namespace: "a", title: "Item-0"),
            (namespace: "b", title: "One"),
        ]
        let current: [ItemIdentity.Item] = [
            (namespace: "a", title: "OneDrive"),
            (namespace: "b", title: "Two"),
        ]
        #expect(ItemIdentity.learnTitleChangingOwners(previous: previous, current: current, excluding: []) == ["b"])
    }

    // MARK: holzBar's own items

    @Test("holzBar's own items are never learned, they are keyed by autosave name")
    func ownItemsAreNeverLearned() {
        // holzBar tags its items by their autosave names, which are identifiers and never live
        // titles. Learning them would key them by position and break profile and rule keys.
        let own = "com.holzcloud.holzBar"
        let previous: [ItemIdentity.Item] = [(namespace: own, title: "Always"), (namespace: own, title: "Hidden")]
        let current: [ItemIdentity.Item] = [(namespace: own, title: "Visible"), (namespace: own, title: "Other")]
        #expect(ItemIdentity.learnTitleChangingOwners(previous: previous, current: current, excluding: [own]).isEmpty)
        // The exclusion is what protects them: without it the same reads would be learned.
        #expect(ItemIdentity.learnTitleChangingOwners(previous: previous, current: current, excluding: []) == [own])
    }
}
