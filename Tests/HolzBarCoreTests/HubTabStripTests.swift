import Testing
@testable import HolzBarCore

@Suite("HubTabStrip")
struct HubTabStripTests {
    @Test("Stepping moves through the whole list and wraps at both ends")
    func stepping() {
        let tabs = ["overview", "a", "b"]
        #expect(HubTabStrip.step(from: "overview", by: 1, in: tabs) == "a")
        #expect(HubTabStrip.step(from: "b", by: 1, in: tabs) == "overview")
        #expect(HubTabStrip.step(from: "overview", by: -1, in: tabs) == "b")
        #expect(HubTabStrip.step(from: "a", by: -1, in: tabs) == "overview")
        #expect(HubTabStrip.step(from: "overview", by: 7, in: tabs) == "a")
        // An unknown start steps from the Overview.
        #expect(HubTabStrip.step(from: "gone", by: 1, in: tabs) == "a")
        #expect(HubTabStrip.step(from: "gone", by: 1, in: []) == "overview")
    }

    @Test("Selection falls back to the Overview for a tab that does not exist")
    func selectionFallback() {
        #expect(HubTabStrip.selection("b", moduleTabs: ["a", "b"]) == "b")
        #expect(HubTabStrip.selection("zzz", moduleTabs: ["a", "b"]) == "overview")
        #expect(HubTabStrip.selection("a", moduleTabs: []) == "overview")
    }

    @Test("The tabs are the Overview and the modules, each once; a duplicate and a stray overview are dropped")
    func allTabsCleaning() {
        #expect(HubTabStrip.allTabs([]) == ["overview"])
        #expect(HubTabStrip.allTabs(["a", "b"]) == ["overview", "a", "b"])
        #expect(HubTabStrip.allTabs(["a", "overview", "b", "a"]) == ["overview", "a", "b"])
    }
}
