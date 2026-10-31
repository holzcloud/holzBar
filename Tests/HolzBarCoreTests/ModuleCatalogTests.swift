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

    @Test("Calendar is a Preview module of the notch area that asks for the Calendar permission, after Timers")
    func calendarModule() throws {
        let calendar = try #require(ModuleCatalog.all.first { $0.id == "calendar" })
        #expect(calendar.area == .notch)
        #expect(calendar.permission == .calendar)
        #expect(calendar.isPreview)
        #expect(calendar.symbol == "calendar")
        #expect(calendar.titleKey == "Calendar")
        let notch = ModuleCatalog.modules(in: .notch).map(\.id)
        let timersIndex = try #require(notch.firstIndex(of: "timers"))
        let calendarIndex = try #require(notch.firstIndex(of: "calendar"))
        #expect(timersIndex < calendarIndex)
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["calendar"], knownTo: ModuleCatalog.all) == ["calendar"])
    }

    @Test("Live activities is a Preview module of the notch area without a permission, after Calendar")
    func liveActivitiesModule() throws {
        let live = try #require(ModuleCatalog.all.first { $0.id == "live-activities" })
        #expect(live.area == .notch)
        #expect(live.permission == nil)
        #expect(live.isPreview)
        #expect(live.symbol == "waveform")
        #expect(live.titleKey == "Live activities")
        let notch = ModuleCatalog.modules(in: .notch).map(\.id)
        let calendarIndex = try #require(notch.firstIndex(of: "calendar"))
        let liveIndex = try #require(notch.firstIndex(of: "live-activities"))
        #expect(calendarIndex < liveIndex)
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["live-activities"], knownTo: ModuleCatalog.all) == ["live-activities"])
    }

    @Test("File drop is a Preview module of the notch area without a permission, after the hub and Live activities")
    func fileDropModule() throws {
        let drop = try #require(ModuleCatalog.all.first { $0.id == "file-drop" })
        #expect(drop.area == .notch)
        #expect(drop.permission == nil)
        #expect(drop.isPreview)
        #expect(drop.symbol == "tray.and.arrow.down")
        #expect(drop.titleKey == "File drop")
        let notch = ModuleCatalog.modules(in: .notch).map(\.id)
        let hubIndex = try #require(notch.firstIndex(of: "notch-hub"))
        let liveIndex = try #require(notch.firstIndex(of: "live-activities"))
        let dropIndex = try #require(notch.firstIndex(of: "file-drop"))
        #expect(hubIndex < dropIndex)
        #expect(liveIndex < dropIndex)
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["file-drop"], knownTo: ModuleCatalog.all) == ["file-drop"])
    }

    @Test("Display controls is a Preview module of the notch area without a permission, after the hub")
    func displayControlsModule() throws {
        let controls = try #require(ModuleCatalog.all.first { $0.id == "display-controls" })
        #expect(controls.area == .notch)
        #expect(controls.permission == nil)
        #expect(controls.isPreview)
        #expect(controls.symbol == "slider.horizontal.3")
        #expect(controls.titleKey == "Display controls")
        let notch = ModuleCatalog.modules(in: .notch).map(\.id)
        let hubIndex = try #require(notch.firstIndex(of: "notch-hub"))
        let controlsIndex = try #require(notch.firstIndex(of: "display-controls"))
        #expect(hubIndex < controlsIndex)
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["display-controls"], knownTo: ModuleCatalog.all) == ["display-controls"])
    }

    @Test("Accessory alerts is a Preview module of the notch area that needs Bluetooth, after the hub's other modules")
    func accessoryAlertsModule() throws {
        let alerts = try #require(ModuleCatalog.all.first { $0.id == "accessory-alerts" })
        #expect(alerts.area == .notch)
        #expect(alerts.permission == .bluetooth)
        #expect(alerts.isPreview)
        #expect(alerts.symbol == "airpods")
        #expect(alerts.titleKey == "Accessory alerts")
        #expect(alerts.summaryKey == "Tells you when AirPods and other accessories connect, disconnect or run low.")
        let notch = ModuleCatalog.modules(in: .notch).map(\.id)
        let alertsIndex = try #require(notch.firstIndex(of: "accessory-alerts"))
        for other in ["notch-hub", "timers", "calendar", "live-activities", "file-drop", "display-controls"] {
            let index = try #require(notch.firstIndex(of: other))
            #expect(index < alertsIndex)
        }
        #expect(ModuleCatalog.problems(in: ModuleCatalog.all).isEmpty)
        // Off until the user switches it on.
        #expect(ModuleCatalog.enabledIdentifiers([], knownTo: ModuleCatalog.all).isEmpty)
        #expect(ModuleCatalog.enabledIdentifiers(["accessory-alerts"], knownTo: ModuleCatalog.all) == ["accessory-alerts"])
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
            Set(ModuleCatalog.all.compactMap(\.permission)) == [.calendar, .bluetooth],
            """
            A module with a permission needs its sentence (permissionText) and its lookup \
            (isGranted) in ModulesSettingsPane (a module says why before it asks). Teach the \
            pane both, then update this test.
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
