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

    @Test("An item without an app matches by its name only")
    func noApp() {
        #expect(!LayoutListFilter.matches(query: "stats", itemName: "CPU", appName: nil))
        #expect(LayoutListFilter.matches(query: "cp", itemName: "CPU", appName: nil))
    }
}
