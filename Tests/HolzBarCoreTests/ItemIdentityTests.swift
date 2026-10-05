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
}
