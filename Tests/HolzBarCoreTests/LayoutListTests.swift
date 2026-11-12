import Testing
@testable import HolzBarCore

@Suite("Layout list")
struct LayoutListTests {
    @Test("An empty or blank filter lets every row through")
    func emptyQuery() {
        #expect(LayoutListFilter.matches(query: "", itemName: "Wi-Fi", appName: nil))
        #expect(LayoutListFilter.matches(query: "   ", itemName: "Wi-Fi", appName: "Control Centre"))
    }

    @Test("The filter finds the item's or the app's name")
    func itemOrApp() {
        #expect(LayoutListFilter.matches(query: "stats", itemName: "CPU", appName: "Stats"))
        #expect(LayoutListFilter.matches(query: "netz", itemName: "Netzwerk", appName: "Stats"))
        #expect(!LayoutListFilter.matches(query: "clock", itemName: "Netzwerk", appName: "Stats"))
    }

    @Test("Case and diacritics do not matter")
    func caseAndDiacritics() {
        #expect(LayoutListFilter.matches(query: "uberwachung", itemName: "Überwachung", appName: nil))
        #expect(LayoutListFilter.matches(query: "STATS", itemName: "CPU", appName: "Stats"))
    }

    @Test("The siblings of an app are the items with its key")
    func siblings() {
        let items: [(key: String, appKey: String?)] = [("cpu", "com.stats"), ("net", "com.stats"), ("clip", "com.maccy"), ("x", nil)]
        #expect(SiblingGrouping.siblings(of: "com.stats", among: items) == ["cpu", "net"])
        #expect(SiblingGrouping.siblings(of: "com.maccy", among: items) == ["clip"])
        #expect(SiblingGrouping.siblings(of: nil, among: items).isEmpty)
        #expect(SiblingGrouping.siblings(of: "com.none", among: items).isEmpty)
    }

    @Test("An item without an app matches by its name only")
    func noApp() {
        #expect(!LayoutListFilter.matches(query: "stats", itemName: "CPU", appName: nil))
        #expect(LayoutListFilter.matches(query: "cp", itemName: "CPU", appName: nil))
    }
}
