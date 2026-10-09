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
