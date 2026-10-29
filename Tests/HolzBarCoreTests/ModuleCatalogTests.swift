import Testing
@testable import HolzBarCore

@Suite("ModuleCatalog")
struct ModuleCatalogTests {
    private func module(
        _ id: String,
        area: ModuleArea = .notch,
        permission: ModulePermission? = nil
    ) -> ModuleDescriptor {
        ModuleDescriptor(
            id: id,
            area: area,
            symbol: "star",
            titleKey: "\(id).title",
            summaryKey: "\(id).summary",
            permission: permission
        )
    }

    @Test("The shipped catalog keeps its own rules")
    func shippedCatalogIsValid() {
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
    }

    @Test("Widgets is an optional menu bar module without a permission (D-06)")
    func widgetsModule() throws {
        let widgets = try #require(ModuleCatalog.all.first { $0.id == "widgets" })
        #expect(widgets.area == .menuBar)
        #expect(widgets.permission == nil)
        #expect(widgets.symbol == "clock")
        #expect(widgets.titleKey == "Widgets")
        #expect(ModuleCatalog.modules(in: .menuBar).first == widgets)
        // Off until the user switches it on; a switch that was turned on survives a relaunch.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["widgets"], knownTo: ModuleCatalog.all) == ["widgets"])
    }

    @Test("Drag in the Menu Bar is an optional menu bar module without a permission")
    func menuBarDragModule() throws {
        let drag = try #require(ModuleCatalog.all.first { $0.id == "menu-bar-drag" })
        #expect(drag.area == .menuBar)
        #expect(drag.permission == nil)
        #expect(drag.symbol == "arrow.left.arrow.right")
        #expect(drag.titleKey == "Drag in the Menu Bar")
        #expect(ModuleCatalog.modules(in: .menuBar).map(\.id) == ["widgets", "menu-bar-drag", "apple-items"])
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["menu-bar-drag"], knownTo: ModuleCatalog.all) == ["menu-bar-drag"])
    }

    @Test("Apple Items is an optional menu bar module without a permission")
    func appleItemsModule() throws {
        let appleItems = try #require(ModuleCatalog.all.first { $0.id == "apple-items" })
        #expect(appleItems.area == .menuBar)
        #expect(appleItems.permission == nil)
        #expect(appleItems.symbol == "menubar.rectangle")
        #expect(appleItems.titleKey == "Apple Items")
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["apple-items"], knownTo: ModuleCatalog.all) == ["apple-items"])
        #expect(!appleItems.isPreview)
    }

    @Test("The Notch hub is an optional module of the notch area without a permission")
    func notchHubModule() throws {
        let hub = try #require(ModuleCatalog.all.first { $0.id == "notch-hub" })
        #expect(hub.area == .notch)
        #expect(hub.permission == nil)
        #expect(hub.symbol == "capsule.tophalf.filled")
        #expect(hub.titleKey == "Notch hub")
        #expect(ModuleCatalog.modules(in: .notch).first == hub)
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["notch-hub"], knownTo: ModuleCatalog.all) == ["notch-hub"])
    }

    @Test("Timers is a Preview module of the notch area without a permission, after the hub")
    func timersModule() throws {
        let timers = try #require(ModuleCatalog.all.first { $0.id == "timers" })
        #expect(timers.area == .notch)
        #expect(timers.permission == nil)
        #expect(timers.isPreview)
        #expect(timers.symbol == "timer")
        #expect(timers.titleKey == "Timers")
        let notch = ModuleCatalog.modules(in: .notch).map(\.id)
        let hubIndex = try #require(notch.firstIndex(of: "notch-hub"))
        let timersIndex = try #require(notch.firstIndex(of: "timers"))
        #expect(hubIndex < timersIndex)
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["timers"], knownTo: ModuleCatalog.all) == ["timers"])
    }

    @Test("The Modules pane knows everything the catalog ships")
    func modulesPaneKnowsTheCatalog() {
        #expect(
            ModuleCatalog.populatedAreas(of: ModuleCatalog.all) == [.menuBar, .notch],
            """
            A module of another area needs its area title in ModulesSettingsPane. \
            Teach the pane the title, then update this test.
            """
        )
        #expect(
            ModuleCatalog.all.allSatisfy { $0.permission == nil },
            """
            A module with a permission needs its sentence and its lookup (isGranted) in \
            ModulesSettingsPane (a module says why before it asks). Teach the pane both, \
            then update this test.
            """
        )
    }

    @Test("Identifiers are lowercase words joined by single hyphens")
    func identifierForm() {
        #expect(ModuleCatalog.isValidIdentifier("notch-hub"))
        #expect(ModuleCatalog.isValidIdentifier("clipboard"))
        #expect(ModuleCatalog.isValidIdentifier("window-snap-2"))
        #expect(!ModuleCatalog.isValidIdentifier(""))
        #expect(!ModuleCatalog.isValidIdentifier("Notch-Hub"))
        #expect(!ModuleCatalog.isValidIdentifier("notch--hub"))
        #expect(!ModuleCatalog.isValidIdentifier("-notch"))
        #expect(!ModuleCatalog.isValidIdentifier("notch-"))
        #expect(!ModuleCatalog.isValidIdentifier("notch hub"))
        #expect(!ModuleCatalog.isValidIdentifier("nötch"))
        #expect(!ModuleCatalog.isValidIdentifier(String(repeating: "a", count: 41)))
    }

    @Test("Duplicate and malformed identifiers and empty keys are reported")
    func problemsAreReported() {
        let list = [
            module("notch-hub"),
            module("notch-hub"),
            module("Bad Id"),
            ModuleDescriptor(
                id: "empty-key", area: .system, symbol: "", titleKey: "t", summaryKey: "s", permission: nil
            )
        ]
        let problems = ModuleCatalog.problems(in: list)
        #expect(problems.count == 3)
        #expect(problems.contains("Identifier used twice: notch-hub"))
        #expect(problems.contains("Malformed identifier: Bad Id"))
        #expect(problems.contains("Empty symbol or key: empty-key"))
    }

    @Test("Modules are found by area and areas keep the gallery order")
    func areas() {
        let list = [
            module("a-launcher", area: .launcher),
            module("b-notch", area: .notch),
            module("c-notch", area: .notch),
            module("d-capture", area: .capture)
        ]
        #expect(ModuleCatalog.modules(in: .notch, of: list).map(\.id) == ["b-notch", "c-notch"])
        #expect(ModuleCatalog.modules(in: .sound, of: list).isEmpty)
        #expect(ModuleCatalog.populatedAreas(of: list) == [.notch, .launcher, .capture])
    }

    @Test("A stored identifier of a module that no longer exists is dropped")
    func removedModulesDoNotCount() {
        let list = [module("notch-hub"), module("clipboard")]
        let enabled = ModuleCatalog.enabledIdentifiers(["clipboard", "gone", "clipboard"], knownTo: list)
        #expect(enabled == ["clipboard"])
    }

    @Test("Gauge levels follow the thresholds and clamp")
    func gaugeLevels() {
        #expect(GaugeLevel.level(for: 0) == .normal)
        #expect(GaugeLevel.level(for: 0.59) == .normal)
        #expect(GaugeLevel.level(for: 0.6) == .elevated)
        #expect(GaugeLevel.level(for: 0.84) == .elevated)
        #expect(GaugeLevel.level(for: 0.85) == .critical)
        #expect(GaugeLevel.level(for: 1.5) == .critical)
        #expect(GaugeLevel.level(for: -3) == .normal)
        #expect(GaugeLevel.level(for: .nan) == .normal)
        #expect(GaugeLevel.level(for: .infinity) == .normal)
    }
}
